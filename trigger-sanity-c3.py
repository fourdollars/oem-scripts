#!/usr/bin/env python3

import jenkins
import json
import os
import sys
import logging
import argparse
import configparser
from pathlib import Path
from c3_v2_api import request_c3_access_token, get_c3_v2_api

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration file path
OEM_SCRIPTS_CONFIG = Path.home() / '.config' / 'oem-scripts' / 'config.ini'

def get_c3_token():
    """Get machine data from C3 API."""
    # First try to get token from environment
    token = os.environ.get("C3_V2_TOKEN")

    # If no token, try to get credentials and request token
    if not token:
        # First try environment variables
        client_id = os.getenv('C3_CLIENT_ID')
        client_secret = os.getenv('C3_CLIENT_SECRET')

        # If any credentials are missing, try reading from config file
        if not all([client_id, client_secret]):
            client_id = read_config_value(OEM_SCRIPTS_CONFIG, 'c3_client_id')
            client_secret = read_config_value(OEM_SCRIPTS_CONFIG, 'c3_client_secret')

        if not all([client_id, client_secret]):
            logger.error("Missing C3 credentials. Please either:")
            logger.error("1. Set C3_V2_TOKEN environment variable, or")
            logger.error("2. Set C3_CLIENT_ID and C3_CLIENT_SECRET environment variables, or")
            logger.error("3. Configure in ~/.config/oem-scripts/config.ini:")
            logger.error("   [oem-scripts]")
            logger.error("   c3_client_id = your_client_id")
            logger.error("   c3_client_secret = your_client_secret")
            sys.exit(1)

        token = request_c3_access_token(client_id, client_secret)

    return token

def get_linked_labresources():
    """Get list of available CIDs from linked lab resources."""
    token = get_c3_token()  # Reuse token retrieval logic

    # Get the first page of results
    response = get_c3_v2_api(token, '/api/v2/linked-labresource/?datacentre__name__iexact=tel-l4')
    if not response:
        logger.error("Failed to fetch lab resources")
        return []

    available_cids = []
    while True:
        # Extract CIDs that meet our criteria (role=DUT and has IP)
        for cid, data in response.get('results', {}).items():
            if data.get('role') == 'DUT' and data.get('ip_address'):
                available_cids.append(cid)

        # Check if there are more pages
        next_page = response.get('next')
        if not next_page:
            break

        # Get the next page
        response = get_c3_v2_api(token, next_page)
        if not response:
            logger.error("Failed to fetch next page of lab resources")
            break

    return available_cids

def is_supported_kernel_meta(platform_info_dir, project, launchpad_tag, kernel_meta):
    """Check if machine supports the specified kernel meta version in platform info. """
    platform_info_file = Path(platform_info_dir) / project / f'{launchpad_tag}.json'
    if not platform_info_file.exists():
        logger.warning(f"No platform info found for {launchpad_tag}")
        return False

    try:
        with open(platform_info_file) as f:
            platform_info = json.load(f)

        # Compare kernel meta versions
        if platform_info.get('kernel_meta') == f"linux-oem-{kernel_meta}":
            return True
        elif platform_info.get('kernel_meta') == f"linux-generic-hwe-{kernel_meta[:-1]}":
            # transitioned to generic kernel, e.g "linux-generic-hwe-24.04"
            return True

        return False

    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f"Error reading platform info for {launchpad_tag}: {e}")
        return False

def get_supported_cids(available_cids, iso_url, platform_info_dir):
    """Get CIDs for machines that belong to the specified project.

    Args:
        available_cids: List of CIDs to check
        iso_url: URL to the ISO file, used to determine project
        platform_info_dir: Path to the platform-info directory

    Returns:
        list: List of CIDs that match the criteria
    """
    token = get_c3_token()
    supported_cids = []
    iso_file = iso_url.split('/')[-1]  # "somerville-noble-oem-24.04b-next-20241128-125.iso"
    project = iso_file.split('-')[0].lower()  # "somerville"
    kernel_meta = iso_file.split('-')[3].lower()  # "24.04b"

    for cid in available_cids:
        # Get machine details from C3 API
        response = get_c3_v2_api(token, f'/api/v2/machines/{cid}')
        if not response:
            logger.warning(f"Failed to fetch details for CID: {cid}")
            continue

        projects = response.get('projects', [])
        is_project_match = False
        for p in projects:
            # API returns a list of projects
            if p.get('name').lower() == project:
                is_project_match = True
                break

        if response.get('arch_name').lower() == 'x86_64' and is_project_match:
            tag = response.get('launchpad_tag')
            if tag:  # Only process if tag exists
                if is_supported_kernel_meta(platform_info_dir, project, tag, kernel_meta):
                    supported_cids.append(cid)

    return supported_cids

def read_config_value(config_file, key):
    """Read a value from the oem-scripts config file."""
    if not config_file.exists():
        return None

    config = configparser.ConfigParser()
    config.read(config_file)

    try:
        return config['oem-scripts'][key]
    except (KeyError, configparser.Error):
        return None

def get_jenkins_connection():
    """Create a connection to Jenkins server."""
    # First try environment variables
    jenkins_url = os.getenv('JENKINS_URL')
    jenkins_user = os.getenv('JENKINS_USER')
    jenkins_token = os.getenv('JENKINS_TOKEN')

    # If any credentials are missing, try reading from config file
    if not all([jenkins_url, jenkins_user, jenkins_token]):
        if not jenkins_url:
            jenkins_addr = read_config_value(OEM_SCRIPTS_CONFIG, 'jenkins_addr')
            if jenkins_addr:
                jenkins_url = f'http://{jenkins_addr}'

        if not jenkins_user:
            jenkins_user = read_config_value(OEM_SCRIPTS_CONFIG, 'jenkins_user')

        if not jenkins_token:
            jenkins_token = read_config_value(OEM_SCRIPTS_CONFIG, 'jenkins_token')

    if not all([jenkins_url, jenkins_user, jenkins_token]):
        logger.error("Missing Jenkins credentials. Please either:")
        logger.error("1. Set JENKINS_URL, JENKINS_USER, and JENKINS_TOKEN environment variables, or")
        logger.error("2. Configure credentials in ~/.config/oem-scripts/config.ini with format:")
        logger.error("   [oem-scripts]")
        logger.error("   jenkins_addr = your.jenkins.server")
        logger.error("   jenkins_user = your_username")
        logger.error("   jenkins_token = your_api_token")
        sys.exit(1)

    try:
        return jenkins.Jenkins(jenkins_url, username=jenkins_user, password=jenkins_token)
    except Exception as e:
        logger.error(f"Failed to connect to Jenkins: {e}")
        sys.exit(1)

def trigger_job(server, job_name, parameters):
    """Trigger the Jenkins job with given parameters."""
    try:
        server.build_job(job_name, parameters=parameters)
        logger.info(f"Successfully triggered job: {job_name}")
    except Exception as e:
        logger.error(f"Failed to trigger job {job_name}: {e}")
        sys.exit(1)


def parse_arguments():
    parser = argparse.ArgumentParser(description='Trigger infrastructure-checkbox-run job')
    parser.add_argument('--platform-info-dir', required=True, help='Path to platform-info directory')
    parser.add_argument('--iso-url', required=True, help='URL to ISO file')
    parser.add_argument('--job-name', default='infrastructure-checkbox-run', help='Jenkins job name (default: infrastructure-checkbox-run)')
    parser.add_argument('--plan', default='pc-sanity-smoke-test-24-04',
                       help='Target plan under com.canonical.certification name space (default: pc-sanity-smoke-test-24-04)')
    parser.add_argument('--exclude-task', help='Tasks to exclude (e.g., ".*audio/alsa_record_playback_automated")')
    parser.add_argument('--additional-ppas', help='Additional PPAs to include')
    parser.add_argument('--plainbox-conf', help='Content of plainbox.conf for checkbox to override')
    parser.add_argument('--machine-mst-json', help='Content of /var/tmp/checkbox-ng/machine-manifest.json to override')
    parser.add_argument('--clone-manifest', action='store_true', help='Whether to clone the manifest')
    parser.add_argument('--prefix-submission-tarball', help='Prefix for the submission tarball')
    parser.add_argument('--auto-create-bugs-assignee', help='Assignee for automatically created bugs')
    parser.add_argument('--auto-create-bugs-milestone', help='Milestone for automatically created bugs')
    parser.add_argument('--test-flinger-global-timeout', type=int, help='Global timeout for Test Flinger (in seconds)')
    parser.add_argument('--force-run-test-flinger', action='store_true', help='Force run Test Flinger even if the queue is not available')
    parser.add_argument('--send-email-notification', action='store_true', help='Send email notification')
    parser.add_argument('--upload-to-oem-share', action='store_true', help='Upload results to OEM share')
    parser.add_argument('--put-dell-embargo', action='store_true', help='Put Dell embargo on the results')

    args = parser.parse_args()

    return args

def main():
    args = parse_arguments()

    # Set defined Build Parameters for Jenkins Job
    job_name = 'infrastructure-checkbox-run'
    parameters = {
        'IMAGE_URL': args.iso_url,  # verify url?
        'PLAN': args.plan,
    }

    # Add optional parameters only if they were explicitly passed
    if args.exclude_task:
        parameters['EXCLUDE_TASK'] = args.exclude_task

    if args.additional_ppas:
        parameters['ADDITIONAL_PPAS'] = args.additional_ppas

    if args.plainbox_conf:
        parameters['PLAINBOX_CONF'] = args.plainbox_conf

    if args.machine_mst_json:
        parameters['MACHINE_MST_JSON'] = args.machine_mst_json

    if args.clone_manifest:
        parameters['CLONE_MANIFEST'] = 'true'

    if args.prefix_submission_tarball:
        parameters['PREFIX_SUBMISSION_TARBALL'] = args.prefix_submission_tarball

    if args.auto_create_bugs_assignee:
        parameters['AUTO_CREATE_BUGS_ASSIGNEE'] = args.auto_create_bugs_assignee

    if args.auto_create_bugs_milestone:
        parameters['AUTO_CREATE_BUGS_MILESTONE'] = args.auto_create_bugs_milestone

    if args.test_flinger_global_timeout:
        parameters['TEST_FLINGER_GLOBAL_TIMEOUT'] = str(args.test_flinger_global_timeout)

    if args.force_run_test_flinger:
        parameters['FORCE_RUN_TEST_FLINGER'] = 'true'

    if args.send_email_notification:
        parameters['SEND_EMAIL_NOTIFICATION'] = 'true'

    if args.upload_to_oem_share:
        parameters['UPLOAD_TO_OEM_SHARE'] = 'true'

    if args.put_dell_embargo:
        parameters['PUT_DELL_EMBARGO'] = 'true'

    # Get CIDs which are online in Lab4 (IoT and PC)
    available_cids = get_linked_labresources()
    if not available_cids:
        logger.error("No available CIDs found")
        sys.exit(1)

    # Get CIDs suitable for this ISO provisioning
    supported_cids = get_supported_cids(available_cids, args.iso_url, args.platform_info_dir)
    if not supported_cids:
        logger.error("No supported CIDs found for the given ISO file")
        sys.exit(1)

    jenkins_server = get_jenkins_connection()
    for cid in supported_cids:
        parameters['CID'] = cid
        trigger_job(jenkins_server, job_name, parameters)

if __name__ == "__main__":
    main()