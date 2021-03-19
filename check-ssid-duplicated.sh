#!/bin/bash

function usage()
{
    echo ""
    echo "Usage:"
    echo -n "  bash $(basename "$0")"
    echo -n " --project=[stella,sutton,somerville]"
    echo -n " \"\${SSID1} \${SSID2} ... \${SSIDn}\""
    echo ""
    echo "Example:"
    echo "  bash $(basename "$0") --project=stella \"886D 8870\""
    exit 1
}

DIR=$(mktemp -d -p "$PWD")
PROJECT=""

function cleanup(){
    cd - > /dev/null 2>&1 || true
    sudo rm -r "$DIR"
}

[[ "$#" -ne 2 ]] && usage

case "$1" in
    --project=*)
        eval PROJECT="${1#*=}"
        shift
        ;;
esac

if [ "$PROJECT" != "stella" ] &&
   [ "$PROJECT" != "somerville" ] &&
   [ "$PROJECT" != "sutton" ]; then
    usage
fi

git clone -q lp:~oem-solutions-engineers/pc-enablement/+git/oem-"${PROJECT}"-projects-meta "$DIR"/meta 2> /dev/null
trap 'cleanup $?' EXIT
cd "${DIR}"/meta || exit 255
for b in $(git branch -r); do
    # shellcheck disable=SC2068
    git show "${b}":debian/modaliases| grep -i ${@// /\\|} && echo "$* duplicated with $b" && exit 255
done
echo "SSID(s) $* are avalible for ${PROJECT} project."
