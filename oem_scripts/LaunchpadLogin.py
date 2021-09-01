#!/usr/bin/python

from configparser import ConfigParser
from launchpadlib.launchpad import Launchpad
from launchpadlib.uris import lookup_service_root
from launchpadlib import credentials
import logging
import os


class ShutUpAndTakeMyTokenAuthorizationEngine(
    credentials.RequestTokenAuthorizationEngine
):
    """This stub class prevents launchpadlib from nulling out consumer_name
    in its demented campaign to force the use of desktop integration. """

    def __init__(
        self,
        service_root,
        application_name=None,
        consumer_name=None,
        credential_save_failed=None,
        allow_access_levels=None,
    ):
        super(ShutUpAndTakeMyTokenAuthorizationEngine, self).__init__(
            service_root, application_name, consumer_name, credential_save_failed
        )


def launchpad_login(pkg, service_root="production", version="devel"):
    """Log into Launchpad API with stored credentials."""
    creds_dir = os.path.expanduser(os.path.join("~", "." + pkg))
    if not os.path.exists(creds_dir):
        os.makedirs(creds_dir, 0o700)
    os.chmod(creds_dir, 0o700)
    api_endpoint = lookup_service_root(service_root)
    consumer_name = pkg
    return Launchpad.login_with(
        consumer_name=consumer_name,
        credentials_file=os.path.join(creds_dir, "launchpad.credentials"),
        service_root=api_endpoint,
        version=version,
        authorization_engine=ShutUpAndTakeMyTokenAuthorizationEngine(
            service_root=api_endpoint, consumer_name=consumer_name
        ),
    )


class LaunchpadLogin:
    """Try to unify all Launchpad login"""

    def __init__(
        self,
        application_name="oem-scripts",
        service_root=None,
        launchpadlib_dir=None,
        version="devel",
        bot=False,
    ):

        if launchpadlib_dir is None:
            launchpadlib_dir = os.path.join(os.environ["HOME"], ".launchpadlib/cache")

        if service_root is None:
            if os.environ.get("LAUNCHPAD_API") == lookup_service_root("staging"):
                service_root = "staging"
            else:
                service_root = "production"

        self.service_root = lookup_service_root(service_root)
        self.service_version = version

        oem_scripts_config_ini = os.path.join(
            os.environ["HOME"], ".config/oem-scripts/config.ini"
        )
        launchpad_token = os.environ.get("LAUNCHPAD_TOKEN")

        if bot:
            logging.info("Using oem-taipei-bot credentials")
            self.lp = launchpad_login("/", service_root)

        elif launchpad_token:
            if launchpad_token == "::":
                logging.info("Using anonymously login")
                self.lp = Launchpad.login_anonymously(application_name, service_root)
            elif ":" in launchpad_token:
                oauth_token, oauth_token_secret, oauth_consumer_key = launchpad_token.split(
                    ":", maxsplit=2
                )
                self.lp = Launchpad.login(
                    oauth_consumer_key,
                    oauth_token,
                    oauth_token_secret,
                    service_root=service_root,
                    cache=launchpadlib_dir,
                    version=version,
                )
            else:
                logging.error(f"invalid LAUNCHPAD_TOKEN '{launchpad_token}'")
                exit(1)

        elif os.environ.get("LAUNCHPAD_API") and os.path.exists(oem_scripts_config_ini):
            logging.info("Using oem-scripts oauth token")
            oem_scripts_config = ConfigParser()
            oem_scripts_config.read(oem_scripts_config_ini)
            config = oem_scripts_config["oem-scripts"]
            self.lp = Launchpad.login(
                config["oauth_consumer_key"],
                config["oauth_token"],
                config["oauth_token_secret"],
                service_root=service_root,
                cache=launchpadlib_dir,
                version=version,
            )
        else:
            logging.info("Using oem-scripts login")
            self.lp = Launchpad.login_with(
                application_name=application_name,
                service_root=service_root,
                launchpadlib_dir=launchpadlib_dir,
                version=version,
            )
