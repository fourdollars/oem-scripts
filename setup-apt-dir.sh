#!/bin/bash
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

export LANG=C

exec 2>&1
set -euo pipefail

CODENAME=
DEBUG=
KEYS=()
LISTS=()
MIRROR=
OUTPUT=
PPA=()
PROPOSED=
OPTS="$(getopt -o c:dho:pm: --long codename:,debug,help,output:,proposed,ppa:,mirror: -n 'setup-apt-dir.sh' -- "$@")"
eval set -- "${OPTS}"
while :; do
    case "$1" in
        ('-h'|'--help')
            cat <<ENDLINE
USAGE:

 $0 [OPTIONS]

OPTIONS:

 -d | --debug
      Print more debug messages

 -h | --help
      Print help manual

 -c | --codename focal
      If not specified, it will use the output of \`lsb_release -c -s\`.

 -m | --mirror mirror://mirrors.ubuntu.com/mirrors.txt
      If not specified, it will use http://archive.ubuntu.com/ubuntu by default.

 -o | --output
      Specify the filename to output the apt dir.

 -p | --proposed
      Enable -proposed channel.

 --ppa ppa:whatever/you-like
      Just make sure you can access it by checking \`get-private-ppa ppa:whatever/you-like\`
ENDLINE
            exit ;;
        ('-d'|'--debug')
            DEBUG=1
            shift ;;
        ('-c'|'--codename')
            CODENAME="$2"
            shift 2;;
        ('-o'|'--output')
            OUTPUT="$2"
            shift 2;;
        ('-p'|'--proposed')
            PROPOSED=1
            shift ;;
        ('--ppa')
            PPA+=("$2")
            shift 2;;
        ('-m'|'--mirror')
            MIRROR="$2"
            shift 2;;
        ('--') shift; break ;;
        (*) break ;;
    esac
done

[ -n "$DEBUG" ] && set -x

if [ -z "$CODENAME" ]; then
    CODENAME="$(lsb_release -c -s)"
fi

if [ -z "$MIRROR" ]; then
    MIRROR="http://archive.ubuntu.com/ubuntu"
fi

if [ -n "$OUTPUT" ] && [ -e "$OUTPUT" ]; then
    echo "$OUTPUT already exists. Please specify other filename."
    exit 1
fi

APTDIR="$(mktemp -d /tmp/apt.XXXXXXXXXX)"
echo "APTDIR=$APTDIR"
mkdir -p "$APTDIR"/var/lib/apt/lists "$APTDIR"/var/lib/dpkg "$APTDIR"/etc/apt/preferences.d "$APTDIR"/var/lib/dpkg
:> "$APTDIR"/var/lib/dpkg/status

if [ "${#PPA[@]}" != "0" ]; then
    while read -r _ url key; do
        KEYS+=("$key")
        LISTS+=("deb [signed-by=$APTDIR/$key.pub] $url $CODENAME main")
    done< <(get-private-ppa "${PPA[@]}")
fi

PUBKEY="3B4FE6ACC0B21F32"

cat > "$APTDIR/etc/apt/sources.list" <<ENDLINE
deb [signed-by=$APTDIR/$PUBKEY.pub arch=amd64] $MIRROR $CODENAME main restricted universe multiverse
deb [signed-by=$APTDIR/$PUBKEY.pub arch=amd64] $MIRROR $CODENAME-updates main restricted universe multiverse
deb [signed-by=$APTDIR/$PUBKEY.pub arch=amd64] $MIRROR $CODENAME-backports main restricted universe multiverse
ENDLINE
if [ -n "$PROPOSED" ]; then
    echo "deb [signed-by=$APTDIR/$PUBKEY.pub arch=amd64] $MIRROR $CODENAME-proposed main restricted universe multiverse" >> "$APTDIR/etc/apt/sources.list"
fi

for list in "${LISTS[@]}"; do
    echo "$list" >> "$APTDIR/etc/apt/sources.list"
done

if ! gpg --fingerprint $PUBKEY >/dev/null 2>&1; then
    gpg --keyserver keyserver.ubuntu.com --recv-key $PUBKEY
fi
gpg --export --armor $PUBKEY > "$APTDIR/$PUBKEY.pub"

for PUBKEY in "${KEYS[@]}"; do
    if ! gpg --fingerprint "$PUBKEY" >/dev/null 2>&1; then
        gpg --keyserver keyserver.ubuntu.com --recv-key "$PUBKEY"
    fi
    gpg --export --armor "$PUBKEY" > "$APTDIR/$PUBKEY.pub"
done

APTOPT=(-o "Dir=$APTDIR" -o "Dir::State::status=$APTDIR/var/lib/dpkg/status")

apt-get "${APTOPT[@]}" update

if [ -z "$OUTPUT" ]; then
    echo "$APTDIR"
else
    echo "$APTDIR" > "$OUTPUT"
fi
