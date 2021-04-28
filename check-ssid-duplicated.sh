#!/bin/bash

function usage()
{
    echo ""
    echo "Usage:"
    echo -n "  bash $(basename "$0")"
    echo -n " --project=[stella,sutton,somerville]"
    echo -n " --pc=\${platform-codename}"
    echo -n " \"\${SSID1},\${SSID2}, ... ,\${SSIDn}\""
    echo ""
    echo "Example:"
    echo "  bash $(basename "$0") --project=stella --pc=audino \"886D,8870\""
    echo "  bash $(basename "$0") --project=stella --pc=grimer \"870B,870C\""
    exit 1
}

DIR=$(mktemp -d -p "$PWD")
PROJECT=""
PLATFORM_CODENAME=""

function cleanup(){
    cd - > /dev/null 2>&1 || true
    rm -rf "$DIR"
}

[[ "$#" -ne 3 ]] && usage

for _ in {1..2}; do
    case "$1" in
        --project=*)
            eval PROJECT="${1#*=}"
            ;;
        --pc=*)
            eval PLATFORM_CODENAME="${1#*=}"
            ;;
    esac
    shift
done

if { [ "$PROJECT" != "stella" ] &&
   [ "$PROJECT" != "somerville" ] &&
   [ "$PROJECT" != "sutton" ]; } ||
   [ -z "$PLATFORM_CODENAME" ]; then
    usage
fi

git clone -q lp:~oem-solutions-engineers/pc-enablement/+git/oem-"${PROJECT}"-projects-meta "$DIR"/meta 2> /dev/null
trap 'cleanup $?' EXIT
cd "${DIR}"/meta || exit 255
for b in $(git branch -r); do
    git show "${b}":debian/modaliases| grep -i "${PLATFORM_CODENAME}" && \
        echo "$PLATFORM_CODENAME duplicated with $b" && exit 255
    git show "${b}":debian/modaliases| grep -ie "${@//,/\\|}" && \
        echo "$* duplicated with $b" && exit 255
done
echo "SSID(s) $* are avalible for ${PROJECT} project."
