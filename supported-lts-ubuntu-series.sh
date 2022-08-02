#!/bin/bash
# -*- coding: utf-8 -*-
# Copyright (C) 2022  Canonical Ltd.
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

export LANG=C

exec 2>&1
set -euo pipefail

FULLNAME=
OPTS="$(getopt -o f --long fullname -n 'supported-lts-ubuntu-series.sh' -- "$@")"
eval set -- "${OPTS}"
while :; do
    case "$1" in
        ('-h'|'--help')
            cat <<ENDLINE
USAGE:

 $0 [OPTIONS]

OPTIONS:

 -f | --fullname
      Print fullname

 -h | --help
      Print help manual
ENDLINE
            exit ;;
        ('-f'|'--fullname')
            FULLNAME=1
            shift ;;
        ('--') shift; break ;;
        (*) break ;;
    esac
done

mapfile -t supported < <(ubuntu-distro-info --supported | sort -r)

for series in "${supported[@]}"; do
    if ubuntu-distro-info --series="$series" --fullname | grep LTS >/dev/null; then
        if [ -z "$FULLNAME" ]; then
            echo "$series"
        else
            ubuntu-distro-info --series="$series" --fullname
        fi
    fi
done
