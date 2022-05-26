#! /usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2020  Canonical Ltd.
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

import logging
import sys


def setup_logging(debug=False, quiet=False):
    if sys.stdout.isatty():
        logging.addLevelName(
            logging.DEBUG, "\033[1;96m%s\033[1;0m" % logging.getLevelName(logging.DEBUG)
        )
        logging.addLevelName(
            logging.INFO, "\033[1;32m%s\033[1;0m" % logging.getLevelName(logging.INFO)
        )
        logging.addLevelName(
            logging.WARNING,
            "\033[1;33m%s\033[1;0m" % logging.getLevelName(logging.WARNING),
        )
        logging.addLevelName(
            logging.ERROR, "\033[1;31m%s\033[1;0m" % logging.getLevelName(logging.ERROR)
        )
        logging.addLevelName(
            logging.CRITICAL,
            "\033[1;41m%s\033[1;0m" % logging.getLevelName(logging.CRITICAL),
        )
    else:
        for level in (
            logging.DEBUG,
            logging.INFO,
            logging.WARNING,
            logging.ERROR,
            logging.CRITICAL,
        ):
            logging.addLevelName(level, "%s" % logging.getLevelName(level))
    if debug:
        logging.basicConfig(
            format="<%(levelname)s> %(message)s",
            level=logging.DEBUG,
            handlers=[logging.StreamHandler(sys.stdout)],
        )
    elif not quiet:
        logging.basicConfig(
            format="<%(levelname)s> %(message)s",
            level=logging.INFO,
            handlers=[logging.StreamHandler(sys.stdout)],
        )
    else:
        logging.basicConfig(
            format="<%(levelname)s> %(message)s",
            handlers=[logging.StreamHandler(sys.stdout)],
        )
