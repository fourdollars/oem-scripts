#! /usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2021  Canonical Ltd.
# Author: Shih-Yuan Lee (FourDollars) <sylee@canonical.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

import subprocess
from logging import debug, info, critical

__version__ = "1.14"

ALLOWED_KERNEL_META_LIST = (
    "linux-oem-20.04d",
    "linux-oem-20.04c",
    "linux-oem-20.04b",
    "linux-oem-20.04",
    "linux-generic-hwe-20.04",
)

SUBSCRIBER_LIST = ("oem-solutions-engineers", "ubuntu-sponsors", "ubuntu-desktop")

TAG_LIST = ["oem-meta-packages", "oem-priority", f"oem-scripts-{__version__}"]


# Python 3.9 supports this.
def remove_prefix(s, prefix):
    return s[len(prefix) :] if s.startswith(prefix) else s


def yes_or_ask(yes: bool, message: str) -> bool:
    if yes:
        print(f"> \033[1;34m{message}\033[1;0m (y/n) y")
        return True
    while True:
        res = input(f"> \033[1;34m{message}\033[1;0m (y/n) ").lower()
        if res not in {"y", "n"}:
            continue
        if res == "y":
            return True
        else:
            return False


def _run_command(
    command: list or tuple, returncode=(0,), env=None, silent=False
) -> (str, str, int):
    if not silent:
        debug("$ " + " ".join(command))
    proc = subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env
    )
    out, err = proc.communicate()

    if out:
        out = out.decode("utf-8").strip()
    if err:
        err = err.decode("utf-8").strip()

    if proc.returncode not in returncode:
        critical(f"return {proc.returncode}")
        if out:
            info(out)
        if err:
            critical(err)
        exit(1)

    if not silent:
        if out:
            debug(out)
        if err:
            debug(err)

    return (out, err, proc.returncode)
