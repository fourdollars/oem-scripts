#!/usr/bin/env python3
# -*- Mode: Python; coding: utf-8; indent-tabs-mode: nil; tab-width: 4 -*-

import argparse
import tempfile
import os
import subprocess
from email import message_from_string
from difflib import SequenceMatcher
import yaml
import requests


def memoize(func):
    cache = {}

    # use <source>_<version> as key to query cache
    def wrapper(*args):
        if args[3] + "_" + args[2] in cache:
            return cache[args[3] + "_" + args[2]]

        result = func(*args)
        cache[args[3] + "_" + args[2]] = result
        return result

    return wrapper


@memoize
def query_deb(pkg, apt_cache, version, source=None):
    if source is None:
        r = subprocess.run(
            [
                "apt",
                "-o",
                "Dir=" + apt_cache,
                "-o",
                "Dir::State::status=" + apt_cache + "/var/lib/dpkg/status",
                "show",
                pkg + "=" + version,
            ],
            capture_output=True,
            check=True,
        )
        if "No packages found" in r.stderr.decode():
            return None

        control = message_from_string(r.stdout.decode())
        source = control.get("Source") if control.get("Source") else pkg

    url = "https://changelogs.ubuntu.com/changelogs/pool/main/"
    r = requests.get(
        url
        + (source[0:4] if source.startswith("lib") else source[0])
        + "/"
        + source
        + "/"
        + source
        + "_"
        + version[version.find(":") + 1 :]
        + "/changelog"
    )

    return {"source": source, "changelog": r.text}


def compare_squashfs(new_squash, old_squash, apt_cache):
    output = {"ADDED": [], "REMOVED": [], "DIFF": []}

    new_squash_list = list(new_squash.keys())
    old_squash_list = list(old_squash.keys())

    deb_list = {}
    for package in new_squash_list:
        is_snap = True if "snap:" in package else False
        if package not in old_squash_list:
            if is_snap:
                output["ADDED"].append({"name": package})
                continue
            result = query_deb(
                package,
                apt_cache,
                new_squash[package]["version"],
                new_squash[package].get("source", None),
            )
            if result is None:
                output["ADDED"].append({"name": package})
                continue
            deb_list[package] = result
            continue
        old_squash_list.remove(package)
        if is_snap:
            if (
                new_squash[package]["version"] != old_squash[package]["version"]
                or new_squash[package]["revision"] != old_squash[package]["revision"]
                or new_squash[package]["tracking"] != old_squash[package]["tracking"]
            ):
                changes = {}
                if old_squash[package]["version"] != new_squash[package]["version"]:
                    changes.update(
                        {
                            "version": old_squash[package]["version"]
                            + " -> "
                            + new_squash[package]["version"]
                        }
                    )
                if old_squash[package]["revision"] != new_squash[package]["revision"]:
                    changes.update(
                        {
                            "revision": old_squash[package]["revision"]
                            + " -> "
                            + new_squash[package]["revision"]
                        }
                    )
                if old_squash[package]["tracking"] != new_squash[package]["tracking"]:
                    changes.update(
                        {
                            "tracking": old_squash[package]["tracking"]
                            + " -> "
                            + new_squash[package]["tracking"]
                        }
                    )
                output["DIFF"].append(
                    {
                        "name": package,
                        "version_change": changes,
                    }
                )
            continue

        if new_squash[package]["version"] != old_squash[package]["version"]:
            result_new = query_deb(
                package,
                apt_cache,
                new_squash[package]["version"],
                new_squash[package].get("source", None),
            )
            result_old = query_deb(
                package,
                apt_cache,
                old_squash[package]["version"],
                old_squash[package].get("source", None),
            )
            if result_new is None or result_old is None:
                output["DIFF"].append({"name": package})
                continue
            changelog_new = result_new["changelog"]
            changelog_old = result_old["changelog"]
            output["DIFF"].append(
                {
                    "name": package,
                    "changelog": changelog_new[: changelog_new.find(changelog_old)],
                }
            )
    for package in old_squash_list:
        is_snap = True if "snap:" in package else False
        if is_snap:
            output["REMOVED"].append({"name": package})
            continue
        result = query_deb(
            package,
            apt_cache,
            old_squash[package]["version"],
            old_squash[package].get("source", None),
        )
        if result is not None:
            for key, value in deb_list.copy().items():
                if (
                    result["source"] == value["source"]
                    and SequenceMatcher(a=package, b=key).ratio() > 0.7
                ):
                    output["DIFF"].append(
                        {
                            "name": key,
                            "changelog": value["changelog"][
                                : value["changelog"].find(result["changelog"])
                            ],
                        }
                    )
                    deb_list.pop(key)
                    break
            else:
                output["REMOVED"].append({"name": package})

    for package in list(deb_list.keys()):
        output["ADDED"].append({"name": package})

    return output


def compare_manifest(new_path, old_path, codename):
    output = {"ADDED": [], "REMOVED": [], "DIFF": []}
    with open(new_path, "rb") as new_yaml_fd:
        new_yaml = yaml.load(new_yaml_fd.read(), Loader=yaml.SafeLoader)
    with open(old_path, "rb") as old_yaml_fd:
        old_yaml = yaml.load(old_yaml_fd.read(), Loader=yaml.SafeLoader)

    # build apt-cache
    apt_cache = tempfile.TemporaryDirectory()
    subprocess.run(
        [
            "setup-apt-dir.sh",
            "--codename",
            codename,
            "--apt-dir",
            apt_cache.name,
            "--enable-source",
        ],
        check=True,
    )

    if new_yaml.keys() != old_yaml.keys():
        print("Error! new YAML and old YAML section not matching")
    for section in new_yaml.keys():
        deb_list = {}
        new_yaml_data = new_yaml[section]
        old_yaml_data = old_yaml[section]

        new_yaml_data_list = list(new_yaml_data.keys())
        old_yaml_data_list = list(old_yaml_data.keys())

        for package in new_yaml_data_list:
            # package is new
            if package not in old_yaml_data_list:
                output_add = {"name": package}
                if ".deb" in package:
                    changelog = new_yaml_data[package].get("changelog", None)
                    source = new_yaml_data[package].get("source", None)
                    if changelog is None or source is None:
                        result = query_deb(
                            os.path.basename(package).split("_")[0],
                            apt_cache.name,
                            new_yaml_data[package]["version"],
                            source,
                        )
                        if result is not None:
                            deb_list[package] = result
                            output_add = None
                    else:
                        deb_list[package] = {"source": source, "changelog": changelog}
                        output_add = None
                if output_add is not None:
                    output["ADDED"].append(output_add)
                continue

            old_yaml_data_list.remove(package)
            # package is differnet
            if new_yaml_data[package]["md5"] != old_yaml_data[package]["md5"]:
                output_diff = {"name": package}
                if ".squash" in package:
                    squashfs_diff = compare_squashfs(
                        new_yaml_data[package]["manifest"],
                        old_yaml_data[package]["manifest"],
                        apt_cache.name,
                    )
                    output_diff["subcomponent"] = squashfs_diff
                if ".deb" in package:
                    # get the changelog of the packages then output the changelog difference
                    changelog_new = new_yaml_data[package].get("changelog", None)
                    changelog_old = old_yaml_data[package].get("changelog", None)
                    if changelog_new is None:
                        result = query_deb(
                            os.path.basename(package).split("_")[0],
                            apt_cache.name,
                            new_yaml_data[package]["version"],
                            new_yaml_data[package].get("source", None),
                        )
                        changelog_new = (
                            result["changelog"] if result is not None else None
                        )
                    if changelog_old is None:
                        result = query_deb(
                            os.path.basename(package).split("_")[0],
                            apt_cache.name,
                            old_yaml_data[package]["version"],
                            old_yaml_data[package].get("source", None),
                        )
                        changelog_old = (
                            result["changelog"] if result is not None else None
                        )
                    if changelog_new is not None and changelog_old is not None:
                        output_diff["changelog"] = changelog_new[
                            : changelog_new[changelog_new.find(changelog_old)]
                        ]
                output["DIFF"].append(output_diff)

        # package is removed
        for package in old_yaml_data_list:
            handled = False
            if ".deb" in package:
                # if deb packages have same source package and similar package name with package in
                # deb_list, record the changelog difference
                changelog = old_yaml_data[package].get("changelog", None)
                source = old_yaml_data[package].get("source", None)
                if changelog is None or source is None:
                    result = query_deb(
                        os.path.basename(package).split("_")[0],
                        apt_cache.name,
                        old_yaml_data[package]["version"],
                        old_yaml_data[package].get("source", None),
                    )
                    if result is not None:
                        changelog = result["changelog"]
                        source = result["source"]
                if changelog is not None and source is not None:
                    for key, value in deb_list.copy().items():
                        if (
                            value["source"] == source
                            and SequenceMatcher(a=package, b=key).ratio() > 0.7
                        ):
                            output["DIFF"].append(
                                {
                                    "name": key,
                                    "changelog": value["changelog"][
                                        : value["changelog"].find(changelog)
                                    ],
                                }
                            )
                            deb_list.pop(key)
                            handled = True
                            break
            if not handled:
                output["REMOVED"].append({"name": package})

        for package in list(deb_list.keys()):
            output["ADDED"].append({"name": package})
    return output


def generate_report(data, output_path):
    with open(output_path, "w") as fd:
        for section, section_data in data.items():
            fd.write(section + "\n")
            for item in section_data:
                fd.write("\t" + item["name"] + "\n")
                subcomponent = item.get("subcomponent", None)
                if subcomponent is not None:
                    for sub_section, sub_section_data in subcomponent.items():
                        if len(sub_section_data) > 0:
                            fd.write("\t" + sub_section + "\n")
                            for sub_item in sub_section_data:
                                fd.write("\t\t" + sub_item["name"] + "\n")
                                changelog = sub_item.get("changelog", None)
                                if changelog is not None:
                                    for s in changelog.split("\n"):
                                        if len(s) > 0:
                                            fd.write("\t\t\t" + s + "\n")
                                version_change = sub_item.get("version_change", None)
                                if version_change is not None:
                                    for key, value in version_change.items():
                                        fd.write("\t\t\t" + key + ":" + value + "\n")
                                fd.write("\n")
                changelog = item.get("changelog", None)
                if changelog is not None:
                    for s in changelog.split("\n"):
                        if len(s) > 0:
                            fd.write("\t\t" + s + "\n")
                    fd.write("\n")


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description="A tool to generate ISO difference from manifests",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--new",
        dest="new_manifest_path",
        action="store",
        required=True,
        help="new manifest path",
    )
    parser.add_argument(
        "--old",
        dest="old_manifest_path",
        action="store",
        required=True,
        help="old manifest path",
    )
    parser.add_argument(
        "--output",
        dest="output_path",
        action="store",
        default="manifest_diff",
        help="ISO difference output path",
    )
    parser.add_argument(
        "--codename", dest="codename", action="store", default="noble", help="codename"
    )
    arguments = parser.parse_args()

    manifest_diff = compare_manifest(
        arguments.new_manifest_path, arguments.old_manifest_path, arguments.codename
    )
    generate_report(manifest_diff, arguments.output_path)
