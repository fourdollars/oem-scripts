#!/bin/bash
set -ex

jenkins_job_for_iso=""
jenkins_job_build_no="lastSuccessfulBuild"
script_on_target_machine="inject_recovery_from_iso.sh"
additional_grub_for_ubuntu_recovery="99_ubuntu_recovery"
user_on_target="ubuntu"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
#TAR="tar -C $temp_folder"
temp_folder="$(mktemp -d -p "$PWD")"
GIT="git -C $temp_folder"
ubuntu_release=""

clear_all() {
    rm -rf "$temp_folder"
    # remove Ubiquity in the end to match factory and Stock Ubuntu image behavior.
    # and it also workaround some debsum error from ubiquity.
    ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" sudo apt-get -o DPkg::Lock::Timeout=-1 purge -y ubiquity
}
trap clear_all EXIT
# shellcheck disable=SC2046
eval set -- $(getopt -o "su:c:j:b:t:h" -l "local-iso:,sync,url:,jenkins-credential:,jenkins-job:,jenkins-job-build-no:,oem-share-url:,oem-share-credential:,target-ip:,ubr,help" -- "$@")

usage() {
    set +x
cat << EOF
Usage:
    # This triggers sync job, downloads the image from oem-share, upload the
    # image to target DUT, and starts recovery.
    $(basename "$0") \\
        -s -u http://10.102.135.50:8080 \\
        -c JENKINS_USERNAME:JENKINS_CREDENTIAL \\
            -j dell-bto-jammy-jellyfish -b 17 \\
        --oem-share-url https://oem-share.canonical.com/share/lyoncore/jenkins/job \\
        --oem-share-credential OEM_SHARE_USERNAME:OEM_SHARE_PASSWORD \\
        -t 192.168.101.68

    # This downloads the image from Jenkins, upload the image to target DUT,
    # and starts recovery.
    $(basename "$0") \\
        -u 10.101.46.50 \\
        -j dell-bto-jammy-jellyfish -b 17 \\
        -t 192.168.101.68

    # This upload the image from local to target DUT, and starts recovery.
    $(basename "$0") \\
        --local-iso ./dell-bto-jammy-jellyfish-X10-20220519-17.iso \\
        -t 192.168.101.68

    # This upload the image from local to target DUT, and starts recovery.  The
    # image is using ubuntu-recovery.
    $(basename "$0") \\
        --local-iso ./pc-stella-cmit-focal-amd64-X00-20210618-1563.iso \\
        --ubr -t 192.168.101.68

Limition:
    It will failed when target recovery partition size smaller than target iso
    file.

The assumption of using this tool:
 - An root account 'ubuntu' on target machine.
 - The root account 'ubuntu' can execute command with root permission with
   \`sudo\` without password.
 - Host executing this tool can access target machine without password over ssh.

OPTIONS:
    --local-iso
      Use local

    -s | --sync
      Trigger sync job \`infrastructure-swift-client\` in Jenkins in --url,
      then download image from --oem-share-url.

    -u | --url
      URL of jenkins server.

    -c | --jenkins-credential
      Jenkins credential in the form of username:password, used with --sync.

    -j | --jenkins-job
      Get iso from jenkins-job.

    -b | --jenkins-job-build-no
      The build number of the Jenkins job assigned by --jenkins-job.

    --oem-share-url
      URL of oem-share, used with --sync.

    --oem-share-credential
      Credential in the form of username:password of lyoncore, used with --sync.

    -t | --target-ip
      The IP address of target machine. It will be used for ssh accessing.
      Please put your ssh key on target machine. This tool no yet support
      keyphase for ssh.

    --ubr
      DUT which using ubuntu recovery (volatile-task).

    -h | --help
      Print this message
EOF
    set -x
exit 1
}

download_preseed() {
    echo " == download_preseed == "
    if [ "${ubr}" == "yes" ]; then
        # TODO: sync togother
        # replace $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-no-secureboot --depth 1
        # Why need it?
        # reokace $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-storage-selecting --depth 1
        mkdir "$temp_folder/preseed/"
        echo "# Ubuntu Recovery configuration preseed

ubiquity ubuntu-oobe/user-interface string dynamic
ubiquity ubuntu-recovery/recovery_partition_filesystem string 0c
ubiquity ubuntu-recovery/active_partition string 1
ubiquity ubuntu-recovery/dual_boot_layout string primary
ubiquity ubuntu-recovery/disk_layout string gpt
ubiquity ubuntu-recovery/swap string dynamic
ubiquity ubuntu-recovery/dual_boot boolean false
ubiquity ubiquity/reboot boolean true
ubiquity ubiquity/poweroff boolean false
ubiquity ubuntu-recovery/recovery_hotkey/partition_label string PQSERVICE
ubiquity ubuntu-recovery/recovery_type string dev
" | tee ubuntu-recovery.cfg
        mv ubuntu-recovery.cfg "$temp_folder/preseed"
        $SCP "$user_on_target"@"$target_ip":/cdrom/preseed/project.cfg ./
        sed -i 's%ubiquity/reboot boolean false%ubiquity/reboot boolean true%' ./project.cfg
        sed -i 's%ubiquity/poweroff boolean true%ubiquity/poweroff boolean false%' ./project.cfg
        mv project.cfg "$temp_folder/preseed"
    else
        # get checkbox pkgs and prepare-checkbox
        # get pkgs to skip OOBE
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-no-secureboot --depth 1
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-storage-selecting --depth 1
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/pack-fish.openssh-fossa --depth 1
    fi

    # install common tool, so that we can use oem-install to create local repository and install packages.
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-oem-image-helper --depth 1 -b oem-fix-misc-cnl-oem-image-helper_fish
    # install packages related to skip oobe
    skip_oobe_branch="master"
    if [ -n "$ubuntu_release" ]; then
        # set ubuntu_release to jammy or focal, depending on detected release
        skip_oobe_branch="$ubuntu_release"
    fi
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-oobe --depth 1 -b "$skip_oobe_branch"
    # get pkgs for ssh key and skip disk checking.
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-misc-for-automation --depth 1 misc_for_automation

    if [ "${ubr}" == "yes" ]; then
    mkdir -p "$temp_folder"/preseed
    cat <<EOF1 > "$temp_folder/preseed/$additional_grub_for_ubuntu_recovery"
#!/bin/bash -e
source /usr/lib/grub/grub-mkconfig_lib
cat <<EOF
menuentry "ubuntu-recovery restore" --hotkey f9 {
        search --no-floppy --hint '(hd0,gpt2)' --set --fs-uuid UUID_OF_RECOVERY_PARTITION
        if [ -s /boot/grub/common.cfg ]; then
            source /boot/grub/common.cfg
        else
            set options="boot=casper automatic-ubiquity noprompt quiet splash"
        fi

        if [ "\\\${grub_platform}" != "efi" ]; then
            if [ -f \\\${prefix}/nomodesetlist.txt ]; then
                if hwmatch \\\${prefix}/nomodesetlist.txt 3; then
                    if [ \\\${match} != 0 ]; then
                        set options="nomodeset \\\$options"
                    fi
                fi
            fi
        fi

        #Support starting from a loopback mount (Only support ubuntu.iso for filename)
        if [ -f /ubuntu.iso ]; then
            loopback loop /ubuntu.iso
            set root=(loop)
            set options="\\\$options iso-scan/filename=/ubuntu.iso"
        fi
        if [ -n "\\\${lang}" ]; then
            set options="\\\$options locale=\\\$lang"
        fi

        linux   /casper/vmlinuz ubuntu-recovery/recovery_type=hdd \\\$options
        initrd  /casper/initrd
}
EOF
EOF1
    cat <<EOF > "$temp_folder/preseed/set_env_for_ubuntu_recovery"
#!/bin/bash -ex
# replace the grub entry which ubuntu_recovery expected
recover_p=\$(lsblk -l | grep efi | cut -d ' ' -f 1 | sed 's/.$/2'/)
UUID_OF_RECOVERY_PARTITION=\$(ls -l /dev/disk/by-uuid/ | grep \$recover_p | awk '{print \$9}')
echo partition = \$UUID_OF_RECOVERY_PARTITION
sed -i "s/UUID_OF_RECOVERY_PARTITION/\$UUID_OF_RECOVERY_PARTITION/" push_preseed/preseed/$additional_grub_for_ubuntu_recovery
sudo rm -f /etc/grub.d/99_dell_recovery || true
chmod 766 push_preseed/preseed/$additional_grub_for_ubuntu_recovery
sudo cp push_preseed/preseed/$additional_grub_for_ubuntu_recovery /etc/grub.d/

# Force changing the recovery partition label to PQSERVICE for ubuntu-recovery
sudo fatlabel /dev/\$recover_p PQSERVICE
EOF
    fi

    return 0
}
push_preseed() {
    echo " == download_preseed == "
    $SSH "$user_on_target"@"$target_ip" rm -rf push_preseed
    $SSH "$user_on_target"@"$target_ip" mkdir -p push_preseed
    $SSH "$user_on_target"@"$target_ip" touch push_preseed/SUCCSS_push_preseed
    $SSH "$user_on_target"@"$target_ip" sudo rm -f /cdrom/SUCCSS_push_preseed

    if [ "${ubr}" == "yes" ]; then
        $SCP -r "$temp_folder/preseed" "$user_on_target"@"$target_ip":~/push_preseed || $SSH "$user_on_target"@"$target_ip" sudo rm -f push_preseed/SUCCSS_push_preseed
    else
        for folder in pack-fish.openssh-fossa oem-fix-misc-cnl-no-secureboot oem-fix-misc-cnl-skip-oobe oem-fix-misc-cnl-skip-storage-selecting; do
            tar -C "$temp_folder"/$folder -zcvf "$temp_folder"/$folder.tar.gz .
            $SCP "$temp_folder/$folder".tar.gz "$user_on_target"@"$target_ip":~
            $SSH "$user_on_target"@"$target_ip" tar -C push_preseed -zxvf $folder.tar.gz || $SSH "$user_on_target"@"$target_ip" sudo rm -f push_preseed/SUCCSS_push_preseed
        done
    fi

    for folder in misc_for_automation oem-fix-misc-cnl-oem-image-helper oem-fix-misc-cnl-skip-oobe; do
        tar -C "$temp_folder"/$folder -zcvf "$temp_folder"/$folder.tar.gz .
        $SCP "$temp_folder/$folder".tar.gz "$user_on_target"@"$target_ip":~
        $SSH "$user_on_target"@"$target_ip" tar -C push_preseed -zxvf $folder.tar.gz || $SSH "$user_on_target"@"$target_ip" sudo rm -f push_preseed/SUCCSS_push_preseed
    done

    $SSH "$user_on_target"@"$target_ip" sudo cp -r push_preseed/* /cdrom/
    return 0
}
inject_preseed() {
    echo " == inject_preseed == "
    $SSH "$user_on_target"@"$target_ip" rm -rf /tmp/SUCCSS_inject_preseed
    download_preseed && \
    push_preseed
    $SCP "$user_on_target"@"$target_ip":/cdrom/SUCCSS_push_preseed "$temp_folder" || usage

    if [ "${ubr}" == "yes" ]; then
        $SSH "$user_on_target"@"$target_ip" bash \$HOME/push_preseed/preseed/set_env_for_ubuntu_recovery || usage
    fi
    $SSH "$user_on_target"@"$target_ip" touch /tmp/SUCCSS_inject_preseed
}

download_image() {
    img_path=$1
    img_name=$2
    user=$3

    echo "downloading $img_name from $img_path"
    curl_cmd=(curl --retry 3 -S)
    if [ -n "$user" ]; then
        curl_cmd+=(--user "$user")
    fi

    pushd "$temp_folder"
    "${curl_cmd[@]}" -O "$img_path/$img_name".md5sum
    "${curl_cmd[@]}" -O "$img_path/$img_name" 2> /dev/null
    if ! md5sum -c "$img_name".md5sum; then
        echo "error: failed to check image with md5sum"
        exit 1
    fi
    local_iso="$PWD/$img_name"
    popd
}

download_from_jenkins() {
    path="ftp://$jenkins_url/jenkins_host/jobs/$jenkins_job_for_iso/builds/$jenkins_job_build_no/archive/out"
    img_name=$(wget -q "$path/" -O - | grep -o 'href=.*iso"' | awk -F/ '{print $NF}' | tr -d \")
    download_image "$path" "$img_name"
}

sync_to_swift() {
    if [ -z "$jenkins_url" ] ; then
        echo "error: --url not set"
        exit 1
    elif [ -z "$jenkins_credential" ]; then
        echo "error: --jenkins-credential not set"
        exit 1
    elif [ -z "$jenkins_job_for_iso" ]; then
        echo "error: --jenkins-job not set"
        exit 1
    elif [ -z "$jenkins_job_build_no" ]; then
        echo "error: --jenkins-job-build-no not set"
        exit 1
    elif [ -z "$oem_share_url" ]; then
        echo "error: --oem-share-url not set"
        exit 1
    elif [ -z "$oem_share_credential" ]; then
        echo "error: --oem-share-credential not set"
        exit 1
    fi

    jenkins_job_name="infrastructure-swift-client"
    jenkins_job_url="$jenkins_url/job/$jenkins_job_name/buildWithParameters"
    curl_cmd=(curl --retry 3 --max-time 10 -sS)
    headers_path="$temp_folder/build_request_headers"

    echo "sending build request"
    "${curl_cmd[@]}" --user "$jenkins_credential" -X POST -D "$headers_path" "$jenkins_job_url" \
        --data option=sync \
        --data "jenkins_job=$jenkins_job_for_iso" \
        --data "build_no=$jenkins_job_build_no"

    echo "getting job id from queue"
    queue_url=$(grep '^Location: ' "$headers_path" | awk '{print $2}' | tr -d '\r')
    duration=0
    timeout=60
    url=
    until [ -n "$timeout" ] && [[ $duration -ge $timeout ]]; do
        url=$("${curl_cmd[@]}" --user "$jenkins_credential" "${queue_url}api/json" | jq -r '.executable | .url')
        if [ "$url" != "null" ]; then
            break
        fi
        sleep 5
        duration=$((duration+5))
    done
    if [ "$url" = "null" ]; then
        echo "error: sync job was not created in time"
        exit 1
    fi

    echo "polling build status"
    duration=0
    timeout=1800
    until [ -n "$timeout" ] && [[ $duration -ge $timeout ]]; do
        result=$("${curl_cmd[@]}" --user "$jenkins_credential" "${url}api/json" | jq -r .result)
        if [ "$result" = "SUCCESS" ]; then
            break
        fi
        sleep 30
        duration=$((duration+30))
    done
    if [ "$result" != "SUCCESS" ]; then
        echo "error: sync job has not been done in time"
        exit 1
    fi

    oem_share_path="$oem_share_url/$jenkins_job_for_iso/$jenkins_job_build_no"
    img_name=$(curl -sS --user "$oem_share_credential" "$oem_share_path/" | grep -o 'href=.*iso"' | tr -d \")
    img_name=${img_name#"href="}
    download_image "$oem_share_path" "$img_name" "$oem_share_credential"
}

download_iso() {
    if [ "$enable_sync_to_swift" = true ]; then
        sync_to_swift
    else
        download_from_jenkins
    fi
}

inject_recovery_iso() {
    if [ -z "$local_iso" ]; then
        download_iso
    fi

    img_name="$(basename "$local_iso")"
    if [ -z "${img_name##*stella*}" ] ||
       [ -z "${img_name##*sutton*}" ]; then
        ubr="yes"
    fi
    if [ -z "${img_name##*jammy*}" ]; then
        ubuntu_release="jammy"
    elif [ -z "${img_name##*focal*}" ]; then
        ubuntu_release="focal"
    fi
    rsync_opts="--exclude=efi --delete --temp-dir=/var/tmp/rsync"
    $SCP "$local_iso" "$user_on_target"@"$target_ip":~/
cat <<EOF > "$temp_folder/$script_on_target_machine"
#!/bin/bash
set -ex
sudo umount /cdrom /mnt || true
sudo mount -o loop $img_name /mnt && \
recover_p=\$(lsblk -l | grep efi | cut -d ' ' -f 1 | sed 's/.$/2'/) && \
sudo mount /dev/\$recover_p /cdrom && \
df | grep "cdrom\|mnt" | awk '{print \$2" "\$6}' | sort | tail -n1 | grep -q cdrom && \
sudo mkdir -p /var/tmp/rsync && \
sudo rsync -alv /mnt/ /cdrom/ $rsync_opts && \
sudo cp /mnt/.disk/ubuntu_dist_channel /cdrom/.disk/ && \
touch /tmp/SUCCSS_inject_recovery_iso
EOF
    $SCP "$temp_folder"/"$script_on_target_machine" "$user_on_target"@"$target_ip":~/
    $SSH "$user_on_target"@"$target_ip" chmod +x "\$HOME/$script_on_target_machine"
    $SSH "$user_on_target"@"$target_ip" "\$HOME/$script_on_target_machine"
    $SCP "$user_on_target"@"$target_ip":/tmp/SUCCSS_inject_recovery_iso "$temp_folder" || usage
}
prepare() {
    echo "prepare"
    inject_recovery_iso
    inject_preseed
}

poll_recovery_status() {
    while(:); do
        if [ "$($SSH "$user_on_target"@"$target_ip"  systemctl is-active ubiquity)" = "inactive" ] ; then
           break
        fi
        sleep 180
    done
}

do_recovery() {
    if [ "${ubr}" == "yes" ]; then
        echo GRUB_DEFAULT='"ubuntu-recovery restore"' | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        echo GRUB_TIMEOUT_STYLE=menu | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        echo GRUB_TIMEOUT=5 | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        $SSH "$user_on_target"@"$target_ip" sudo update-grub
        $SSH "$user_on_target"@"$target_ip" sudo reboot &
    else
        $SSH "$user_on_target"@"$target_ip" sudo dell-restore-system -y &
    fi
    sleep 300 # sleep to make sure the target system has been rebooted to recovery mode.
    poll_recovery_status
}

main() {
    while [ $# -gt 0 ]
    do
        case "$1" in
            --local-iso)
                shift
                local_iso="$1"
                ;;
            -s | --sync)
                enable_sync_to_swift=true
                ;;
            -u | --url)
                shift
                jenkins_url="$1"
                ;;
            -c | --jenkins-credential)
                shift
                jenkins_credential="$1"
                ;;
            -j | --jenkins-job)
                shift
                jenkins_job_for_iso="$1"
                ;;
            -b | --jenkins-job-build-no)
                shift
                jenkins_job_build_no="$1"
                ;;
            --oem-share-url)
                shift
                oem_share_url="$1"
                ;;
            --oem-share-credential)
                shift
                oem_share_credential="$1"
                ;;
            -t | --target-ip)
                shift
                target_ip="$1"
                ;;
            --ubr)
                ubr="yes"
                ;;
            -h | --help)
                usage 0
                exit 0
                ;;
            --)
                ;;
            *)
                echo "Not recognize $1"
                usage
                exit 1
                ;;
           esac
           shift
    done
    prepare
    do_recovery
    clear_all
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
