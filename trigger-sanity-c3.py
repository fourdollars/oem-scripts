#!/usr/bin/env python3

import jenkins
import os
import sys
import logging
import argparse
import configparser
from pathlib import Path

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

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
        config_file = Path.home() / '.config' / 'oem-scripts' / 'config.ini'

        if not jenkins_url:
            jenkins_addr = read_config_value(config_file, 'jenkins_addr')
            if jenkins_addr:
                jenkins_url = f'http://{jenkins_addr}'

        if not jenkins_user:
            jenkins_user = read_config_value(config_file, 'jenkins_user')

        if not jenkins_token:
            jenkins_token = read_config_value(config_file, 'jenkins_token')

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
    parser = argparse.ArgumentParser(description='Trigger Jenkins infrastructure-checkbox-run job')

    # Required arguments
    parser.add_argument('--cid', required=True, help='CID of DUT')
    parser.add_argument('--image-url', help='Download ISO and run TF oem_autoinstall connector to provision the DUT')
    parser.add_argument('--plan', default='pc-sanity-smoke-test-24-04',
                       help='Target plan under com.canonical.certification name space (default: pc-sanity-smoke-test-24-04)')

    # Optional arguments
    parser.add_argument('--exclude-task', help='Tasks to exclude (e.g., ".*audio/alsa_record_playback_automated")')
    parser.add_argument('--additional-ppas', help='Additional PPAs to include')
    parser.add_argument('--plainbox-conf', help='Content of plainbox.conf for checkbox to override')
    parser.add_argument('--machine-mst-json', help='Content of /var/tmp/checkbox-ng/machine-manifest.json to override')
    parser.add_argument('--clone-manifest', action='store_true', help='Whether to clone the manifest')

    # Additional parameters
    parser.add_argument('--prefix-submission-tarball', help='Prefix for the submission tarball')
    parser.add_argument('--auto-create-bugs-assignee', help='Assignee for automatically created bugs')
    parser.add_argument('--auto-create-bugs-milestone', help='Milestone for automatically created bugs')
    parser.add_argument('--test-flinger-global-timeout', type=int, help='Global timeout for Test Flinger (in seconds)')
    parser.add_argument('--force-run-test-flinger', action='store_true', help='Force run Test Flinger even if the queue is not available')
    parser.add_argument('--send-email-notification', action='store_true', help='Send email notification')
    parser.add_argument('--upload-to-oem-share', action='store_true', help='Upload results to OEM share')
    parser.add_argument('--put-dell-embargo', action='store_true', help='Put Dell embargo on the results')

    args = parser.parse_args()

    # Validate that either image-url or plan is provided
    if not args.image_url and not args.plan:
        parser.error("Either --image-url or --plan must be provided")

    return args

def main():
    args = parse_arguments()

    # Start with required parameters
    parameters = {
        'CID': args.cid,
    }

    # Add image-url and plan if provided
    if args.image_url:
        parameters['IMAGE_URL'] = args.image_url
    if args.plan:
        parameters['PLAN'] = args.plan

    # Add optional parameters only if they were explicitly set
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

    # Connect to Jenkins
    jenkins_server = get_jenkins_connection()

    # Job name
    job_name = 'infrastructure-checkbox-run'

    # Trigger the job
    trigger_job(jenkins_server, job_name, parameters)

if __name__ == "__main__":
    main()