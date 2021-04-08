#!/bin/bash
set -ex

jenkins_job_for_iso=""
jenkins_job_build_no="lastSuccessfulBuild"
script_on_target_machine="inject_recovery_from_iso.sh"
user_on_target="ubuntu"
SSH="ssh -o StrictHostKeyChecking=no"
SCP="scp -o StrictHostKeyChecking=no"
#TAR="tar -C $temp_folder"
temp_folder="$(mktemp -d -p "$PWD")"
GIT="git -C $temp_folder"

clear_all() {
    rm -rf "$temp_folder"
}
trap clear_all EXIT
# shellcheck disable=SC2046
eval set -- $(getopt -o "hj:t:b:u:" -l "help,target-ip:,jenkins-job:,local-iso:,url:" -- "$@")

usage() {
cat << EOF
usage:
$(basename "$0") -u <jenkins url> -j <jenkins-job-name> -b <jenkins-job-build-no> -t <target-ip> [-h|--help] [--dry-run]
$(basename "$0") --local-iso <path to local iso file> -t <target-ip> [-h|--help] [--dry-run]

Limition:
    It will failed when target recovery partition size smaller than target iso file.

The assumption of using this tool:
 - An root account 'ubuntu' on target machine.
 - The root account 'ubuntu' can execute command with root permission with \`sudo\` without password.
 - Host executing this tool can access target machine without password over ssh.

OPTIONS:
    -u|--url                    The url of jenkins server.
    -j|--jenkins-job            Get iso from jenkins-job. The default is "dell-bto-focal-fossa-edge-alloem".
    -b|--jenkins-job-build-no   The build number of the Jenkins job assigned by -j|--jenkins-job.
    -t|--target-ip  The IP address of target machine. It will be used for ssh accessing.
                    Please put your ssh key on target machine. This tool no yet support keyphase for ssh.
    -h|--help Print this message

Usage:

    $(basename "$0")  -u 10.101.46.50 -j  dell-bto-focal-fossa-edge-alloem -b 3 -t 192.168.101.68

    $(basename "$0") --local-iso ./dell-bto-focal-fossa-edge-alloem-X73-20210302-3.iso -t 192.168.101.68

EOF
exit 1
}

download_preseed() {
    echo " == download_preseed == "
    # get checkbox pkgs and prepare-checkbox
    # get pkgs to skip OOBE
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-no-secureboot --depth 1
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-oobe --depth 1
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-storage-selecting --depth 1
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/pack-fish.openssh-fossa --depth 1

    # get pkgs for ssh key and skip disk checking.
    $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-misc-for-automation --depth 1 misc_for_automation

    return 0
}
push_preseed() {
    echo " == download_preseed == "
    $SSH "$user_on_target"@"$target_ip" rm -rf push_preseed
    $SSH "$user_on_target"@"$target_ip" mkdir -p push_preseed
    $SSH "$user_on_target"@"$target_ip" touch push_preseed/SUCCSS_push_preseed
    $SSH "$user_on_target"@"$target_ip" sudo rm -f /cdrom/SUCCSS_push_preseed

    for folder in pack-fish.openssh-fossa misc_for_automation oem-fix-misc-cnl-no-secureboot oem-fix-misc-cnl-skip-oobe oem-fix-misc-cnl-skip-storage-selecting; do
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
    scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/cdrom/SUCCSS_push_preseed "$temp_folder" || usage
    $SSH "$user_on_target"@"$target_ip" touch /tmp/SUCCSS_inject_preseed
}

inject_recovery_iso() {
    if [ -n "$local_iso" ]; then
        img_name="$(basename "$local_iso")"
        scp -o StrictHostKeyChecking=no "$local_iso" "$user_on_target"@"$target_ip":~/
cat <<EOF > "$temp_folder/$script_on_target_machine"
#!/bin/bash
set -ex
sudo umount /cdrom /mnt || true
sudo mount -o loop $img_name /mnt && \
sudo mount /dev/\$(lsblk -l | grep efi | cut -d ' ' -f 1 | sed 's/.$/2'/) /cdrom && \
df | grep "cdrom\|mnt" | awk '{print \$2" "\$6}' | sort | tail -n1 | grep -q cdrom && \
sudo mkdir -p /var/tmp/rsync && \
sudo rsync -alv /mnt/ /cdrom/ --exclude=factory/grub.cfg* --exclude=efi/boot --exclude=.disk/casper-uuid --exclude=.disk/info --exclude=.disk/info.recovery --exclude=efi.factory --delete --exclude=casper/filesystem.squashfs --temp-dir=/var/tmp/rsync && \
sudo cp /mnt/.disk/ubuntu_dist_channel /cdrom/.disk/ && \
touch /tmp/SUCCSS_inject_recovery_iso
EOF
        scp -o StrictHostKeyChecking=no "$temp_folder"/"$script_on_target_machine" "$user_on_target"@"$target_ip":~/
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" chmod +x "\$HOME/$script_on_target_machine"
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" "\$HOME/$script_on_target_machine"
        scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/tmp/SUCCSS_inject_recovery_iso "$temp_folder" || usage
    else
        img_jenkins_out_url="ftp://$jenkins_url/jenkins_host/jobs/$jenkins_job_for_iso/builds/$jenkins_job_build_no/archive/out"
        img_name="$(wget -q "$img_jenkins_out_url/" -O - | grep -o 'href=.*iso"' | awk -F/ '{print $NF}' | tr -d \")"
        pushd "$temp_folder" || usage
        wget "$img_jenkins_out_url/$img_name".md5sum
        md5sum -c "$img_name".md5sum || wget "$img_jenkins_out_url"/"$img_name"
        md5sum -c "$img_name".md5sum || usage
        local_iso="$PWD/$img_name"
        popd
        inject_recovery_iso
    fi
}
prepare() {
    echo "prepare"
    inject_recovery_iso
    inject_preseed
}

poll_recovery_status() {
    while(:); do
        if $SSH "$user_on_target"@"$target_ip" ubuntu-report show; then
           break
        fi
        sleep 180
    done
}

do_recovery() {
    ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" sudo dell-restore-system -y &
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
            -u | --url)
                shift
                jenkins_url="$1"
                ;;
            -j | --jenkins-job)
                shift
                jenkins_job_for_iso="$1"
                ;;
            -b | --jenkins-job-build-no)
                shift
                jenkins_job_build_no="$1"
                ;;
            -t | --target-ip)
                shift
                target_ip="$1"
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
