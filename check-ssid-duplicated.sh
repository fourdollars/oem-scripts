#!/bin/bash
# Description: Check if the given ssid(s) and platform codename are duplicated
#   with the existing branches in the project.
# Exit code:
#  0: no duplicate
#  1: duplicate with either ssid or platform codename
#  2: duplicate with both ssid and platform codename
#  3: other errors

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
    exit 3
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

# check_duplicate
# Parameters:
#   $1: [str] branch name
#   $2: [','.join(list[str])] ssids
#   $3: [str] platform codename
#   $4: [str] project name
# Returns:
#   0: no duplicate
#   1: duplicate with either ssid or platform codename
#   2: duplicate with both
function check_duplicate() {
    local raw ssids metapkg_names ret all_matched

    ret=0
    raw=$(git show "$1":debian/modaliases 2> /dev/null)

    if [ -z "$raw" ]; then
        return $ret
    fi

    ssids=$(echo "$raw" | awk '{print $2}')
    metapkg_names=$(echo "$raw" | awk '{print $4}' | uniq)

    all_matched=1
    for ssid in ${2//,/ }; do
        matched_ssid=$(echo "$ssids" | grep -ie "$ssid")
        if [ -z "$matched_ssid" ]; then
            all_matched=0
        else
            echo "${1//origin\//}: $ssid is duplicated with $matched_ssid"
            ret=1
        fi
    done

    for metapkg_name in $metapkg_names; do
        if [ "$metapkg_name" == "oem-$4-$3-meta" ]; then
            echo "${1//origin\//}: $3 is duplicated with $metapkg_name"
            ret=$((ret + 1))
            break
        fi
    done

    if [ "$ret" -eq 2 ] && [ "$all_matched" -eq 0 ]; then
        ret=1
    fi

    return $ret
}

git clone -q lp:~oem-solutions-engineers/pc-enablement/+git/oem-"${PROJECT}"-projects-meta "$DIR"/meta 2> /dev/null
trap 'cleanup $?' EXIT
cd "${DIR}"/meta || exit 3

NON_FATAL=0
for b in $(git branch -r); do
    check_duplicate "$b" "$*" "$PLATFORM_CODENAME" "$PROJECT"
    exit_code=$?
    if [ "$exit_code" -eq 1 ]; then
        exit 1
    fi
    if [ "$exit_code" -eq 2 ]; then
        NON_FATAL=1
    fi
done

if [ "$NON_FATAL" -eq 1 ]; then
    >&2 echo "WARNING: Some ssids or platform codenames are duplicated."
    exit 2
fi

echo "SSID(s) $* are avalible for ${PROJECT} project."
