#!/bin/bash
# Description: Check if the given ssid(s) and platform codename are duplicated
#   with the existing branches in the project.
#
# Environment variables:
#  WORKING_DIR: [str] working directory to clone the project meta
#               (default: a temp directory that will be removed after execution)
#
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
    echo -n " [--series=\${ubuntu-series} (default: $SERIES_DEFAULT)] "
    echo -n " \"\${SSID1},\${SSID2}, ... ,\${SSIDn}\""
    echo ""
    echo "Example:"
    echo "  bash $(basename "$0") --project=stella --pc=audino \"886D,8870\""
    echo "  bash $(basename "$0") --project=stella --pc=grimer --series=jammy \"870B,870C\""
    exit 3
}

PROJECT=""
PLATFORM_CODENAME=""
SERIES=""
SERIES_DEFAULT="jammy"

function cleanup(){
    cd - > /dev/null 2>&1 || true
    rm -rf "$WORKING_DIR"
}

[[ "$#" -lt 3 ]] && usage

for _ in {1..3}; do
    case "$1" in
        --project=*)
            eval PROJECT="${1#*=}"
            ;;
        --pc=*)
            eval PLATFORM_CODENAME="${1#*=}"
            ;;
        --series=*)
            eval SERIES="${1#*=}"
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$(mktemp -d -p "$PWD")
    trap 'cleanup $?' EXIT
elif [ ! -d "$WORKING_DIR" ]; then
    mkdir -p "$WORKING_DIR"
fi

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
        matched_ssid=$(echo "$ssids" | grep -e "${ssid^^}")
        if [ -z "$matched_ssid" ]; then
            all_matched=0
        else
            echo "${1//origin\//}: ${ssid^^} is duplicated with $matched_ssid"
            ret=1
        fi
    done

    function join { local IFS="-"; echo "$*"; }

    local parts n_parts
    for metapkg_name in $metapkg_names; do
        # shellcheck disable=SC2206
        parts=( ${metapkg_name//-/ } )
        n_parts=${#parts[@]}

        # oem-<project.group?>-<codename>-meta
        if [ "$n_parts" -lt 4 ]                             \
            || [ "${parts[0]}" != "oem" ]                   \
            || [ "${parts[$((n_parts - 1))]}" != "meta" ]   \
            || [[ "${parts[1]}" != "$4"* ]];
        then
            >&2 echo "ERROR: $metapkg_name is not a valid metapackage name."
            continue
        fi

        # Slice and join, ( oem somerville three eyes raven meta ) => three-eyes-raven
        if [ "$(join "${parts[@]:2:$((n_parts - 3))}")" == "$3" ]; then
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

DIR="$WORKING_DIR/$PROJECT-meta"
if [ ! -d "$DIR" ]; then
    # retry git clone if it fails for 10 times
    # (sometimes the git clone fails due to network issue)
    for _ in {1..10}; do
        if git clone -q lp:~oem-solutions-engineers/pc-enablement/+git/oem-"${PROJECT}"-projects-meta "$DIR" &> /dev/null; then
            break
        fi
        if [ "$_" -eq 10 ]; then
            >&2 echo "ERROR: git clone failed."
        else
            >&2 echo "WARNING: git clone failed. Retrying..."
        fi
    done

    cd "$DIR" || exit 3
else
    cd "$DIR" || exit 3
    git fetch -q origin &> /dev/null
fi

NON_FATAL=0
GIT_CMD="git branch -r"
if [ -n "$SERIES" ]; then
    GIT_CMD+=" | grep -e $SERIES-oem$ -e $SERIES-ubuntu$"
else
    GIT_CMD+=" | grep -e $SERIES_DEFAULT-oem$ -e $SERIES_DEFAULT-ubuntu$"
fi

for b in $(eval $GIT_CMD); do
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
