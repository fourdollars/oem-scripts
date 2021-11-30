#!/bin/bash

# shellcheck source=config.sh
source /usr/share/oem-scripts/config.sh 2>/dev/null || source config.sh

HIC_ADDR=""
JENKINS_ADDR=""
verbose=0
dry_run=0
user=$(read_oem_scripts_config jenkins_user)
token=$(read_oem_scripts_config jenkins_token)
project="dummy"
tag=""
exclude_task=""
target_img=""
image_no="lastSuccessfulBuild"
plan="pc-sanity-smoke-test"
cmd_before_run_plan=""
inj_recovery="false"
gitbranch_oem_sanity="master"
auto_create_bugs="false"

usage() {
cat << EOF
Usage:
$(basename "$0") -t <TAG> --dry-run
$(basename "$0") -t <TAG> -p <PROJECT> -u <USER> -k <API_TOKEN>
            [--exclude_task <TASK_TO_EXCLUDE>]
            [--target_img <TARGET_IMAGE>]
            [--image_no <IMAGE_NO>]
            [--plan <PLAN>]
            [--command_before_run_plan <COMMAND>]
            [--inj_recovery <true/false>]
            [--gitbranch_oem_sanity <BRANCH>]
            [--auto_create_bugs <true/false>]
Options:
    -t|--tag                    Platform tag, ex: fossa-arbok
    -p|--project                Project name, default is dummy
    -u|--user                   Jenkins server username
    -k|--token                  Jenkins server user API token
    --exclude_task              sanity-3 parameter exclude_task
    --target_img                sanity-3 parameter target_image
                                (e.g. pc-stella-cmit-focal-amd64)
    --image_no                  sanity-3 parameter image_no, default is lastSuccessfulBuild
                                (e.g. no-provision)
    --plan                      sanity-3 parameter plan, default is pc-sanity-smoke-test
                                (e.g. pc-sanity-smoke-test-no-dgpu-switching)
    --command_before_run_plan   sanity-3 parameter cmd_before_run_plan
    --inj_recovery              sanity-3 parameter inj_recovery, default is false
    --gitbranch_oem_sanity      sanity-3 parameter gitbranch_oem_sanity, default is master
    --auto_create_bugs          sanity-3 parameter auto_create_bugs, default is false
EOF
exit 1
}

check_address() {
    HIC_ADDR=$(read_oem_scripts_config hic_addr)
    JENKINS_ADDR=$(read_oem_scripts_config jenkins_addr)
    if [ -z "$HIC_ADDR" ];then
        read -rp "Input HIC server address: " HIC_ADDR
        HIC_ADDR="${HIC_ADDR/http:\/\//}"
        write_oem_scripts_config hic_addr "${HIC_ADDR}"
    fi
    if [ -z "$JENKINS_ADDR" ];then
        read -rp "Input Jenkins server address: " JENKINS_ADDR
        HIC_ADDR="${JENKINS_ADDR/http:\/\//}"
        write_oem_scripts_config jenkins_addr "${JENKINS_ADDR}"
    fi
}

trigger_sanity_3() {
    local silent
    [ "$verbose" -eq 0 ] && silent="-s"
	#get mapping of tag to skus
    skus=$(curl ${silent} http://"$HIC_ADDR"/q?db=tag | jq -r --arg TAG "$tag" 'with_entries(select(.value | startswith($TAG))) | keys | @sh' | tr -d \')

    ONLINE_IPS=$(curl ${silent} http://"$HIC_ADDR"/q?db=ipo)
    for sku in $skus
    do
        #check sku has valid cid
        format="[0-9]-[0-9]"
        [[ ${sku: -12} =~ $format ]] && cid=${sku: -12} || cid=""
        if [ -z "$cid" ];then
            echo "Can't get CID from $sku"
            continue
        fi
        #check if sku online
        status=$(echo "$ONLINE_IPS" | jq -r --arg CID "$cid" 'with_entries(select(.key | contains($CID))) | keys | @sh' | tr -d \')
        if [ -n "$status" ];then
            echo "trigger job sanity-3-testflinger-$project-$cid-staging"
            if [ $dry_run -eq 0 ];then
                curl -X POST http://"$user":"$token"@"$JENKINS_ADDR"/job/sanity-3-testflinger-"$project"-"$cid"-staging/buildWithParameters\?EXCLUDE_TASK="$exclude_task"\&TARGET_IMG="$target_img"\&IMAGE_NO="$image_no"\&PLAN="$plan"\&CMD_BEFOR_RUN_PLAN="$cmd_before_run_plan"\&INJ_RECOVERY="$inj_recovery"\&GITBRANCH_OEM_SANITY="$gitbranch_oem_sanity"\&AUTO_CREATE_BUGS="$auto_create_bugs"
            fi
        else
            echo "$sku is offline"
        fi
    done
}

main() {
    check_address
    while [ $# -gt 0 ]
    do
        case "$1" in
            -t | --tag)
                shift
                tag=$1
            ;;
            -p | --project)
                shift
                project=$1
            ;;
            -u | --user)
                shift
                user=$1
            ;;
            -k | --token)
                shift
                token=$1
            ;;
            --dry-run)
                dry_run=1
            ;;
            --verbose)
                verbose=1
            ;;
            --exclude_task)
                shift
                exclude_task=$1
            ;;
            --target_img)
                shift
                target_img=$1
            ;;
            --image_no)
                shift
                image_no=$1
            ;;
            --plan)
                shift
                plan=$1
            ;;
            --command_before_run_plan)
                shift
                cmd_before_run_plan=$1
            ;;
            --inj_recovery)
                shift
                inj_recovery=$1
            ;;
            --gitbranch_oem_sanity)
                shift
                gitbranch_oem_sanity=$1
            ;;
            --auto_create_bugs)
                shift
                auto_create_bugs=$1
            ;;
            *)
                echo "Not recognize $1"
                usage
            ;;
        esac
        shift
    done
    if [ -z "$tag" ];then
        echo "Need to input tag"
        usage
    fi
    if [ $dry_run -eq 0 ];then
        if [ -z "$user" ];then
            echo "Need to input user account for jenkins"
            usage
        fi
        if [ -z "$token" ];then
            echo "Need to input user api token for jenkins"
            usage
        fi
    fi
    if [ $verbose -eq 1 ];then
        set -x
    fi
    trigger_sanity_3
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
