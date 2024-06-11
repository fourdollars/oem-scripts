#! /usr/bin/env python3

import sys
import argparse
import os
import logging
from configparser import ConfigParser
import base64
import requests
from requests.auth import HTTPBasicAuth
import json


def request_c3_access_token(client_id: str, secret: str):
    credential = base64.b64encode(
        "{0}:{1}".format(client_id, secret).encode("utf-8")
    ).decode("utf-8")
    headers = {
        "Authorization": "Basic {0}".format(credential),
        "Content-Type": "application/x-www-form-urlencoded",
    }
    data = {"grant_type": "client_credentials", "scope": "read write"}
    response = requests.post(
        "https://certification.canonical.com/oauth2/token/", headers=headers, data=data
    )

    return json.loads(response.text)["access_token"]


def get_c3_v2_api(token: str, api: str):
    host = "https://certification.canonical.com"
    auth = f"Bearer {token}"
    url = host + api
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": auth,
    }
    response = requests.request("GET", url, headers=headers)

    print(response.text)

    if response.status_code == 200:
        return 0

    return 1


def main():
    parser = argparse.ArgumentParser(description="A tool to use C3 v2 REST API")
    op_group = parser.add_mutually_exclusive_group(required=True)
    op_group.add_argument("--get", action="store_true", help="C3 HTTP GET operation")
    op_group.add_argument(
        "--post",
        action="store_true",
        help="C3 HTTP POST operation, not tested yet",
    )
    op_group.add_argument(
        "--put", action="store_true", help="C3 HTTP PUT operation, not tested yet"
    )
    parser.add_argument(
        "api",
        help="API endpoint, refer to https://certification.canonical.com/api/v2/schema",
    )
    args = parser.parse_args()

    oem_scripts_config_ini = os.path.join(
        os.environ["HOME"], ".config/oem-scripts/config.ini"
    )

    access_token = os.environ.get("C3_V2_TOKEN")

    if os.path.exists(oem_scripts_config_ini):
        logging.info(
            "Obtain access token by cliend_id and client_secret in oem-scripts config"
        )
        oem_scripts_config = ConfigParser()
        oem_scripts_config.read(oem_scripts_config_ini)
        config = oem_scripts_config["oem-scripts"]

        if (
            "c3_client_id" not in config.keys()
            or "c3_client_secret" not in config.keys()
        ):
            logging.info(
                f"No c3_client_id and c3_client_secret configured in {oem_scripts_config_ini}"
            )
        else:
            access_token = request_c3_access_token(
                config["c3_client_id"], config["c3_client_secret"]
            )

    if not access_token:
        logging.error("No access token for using C3 v2 API")
        return 1

    if args.get:
        return get_c3_v2_api(access_token, args.api)


if __name__ == "__main__":
    sys.exit(main())
