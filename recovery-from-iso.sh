#!/bin/bash
set -ex

jenkins_job_for_iso=""
jenkins_job_build_no="lastSuccessfulBuild"
script_on_target_machine="inject_recovery_from_iso.sh"
additional_grub_for_ubuntu_recovery="99_ubuntu_recovery"
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
eval set -- $(getopt -o "hj:t:b:u:" -l "help,target-ip:,jenkins-job:,local-iso:,url:,ubr" -- "$@")

usage() {
    set +x
cat << EOF
usage:
$(basename "$0") -u <jenkins url> -j <jenkins-job-name> -b <jenkins-job-build-no> -t <target-ip> [-h|--help] [--dry-run] [--ubr]
$(basename "$0") --local-iso <path to local iso file> -t <target-ip> [-h|--help] [--dry-run] [--ubr]

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
    --ubr         DUT which using ubuntu recovery (volatile-task).
    -h|--help Print this message

Usage:

    $(basename "$0")  -u 10.101.46.50 -j  dell-bto-focal-fossa-edge-alloem -b 3 -t 192.168.101.68

    $(basename "$0") --local-iso ./dell-bto-focal-fossa-edge-alloem-X73-20210302-3.iso -t 192.168.101.68

    $(basename "$0") --local-iso ./pc-stella-cmit-focal-amd64-X00-20210618-1563.iso --ubr -t 192.168.101.68

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
        mkdir $temp_folder/preseed/
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
        mv ubuntu-recovery.cfg $temp_folder/preseed
        scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/cdrom/preseed/project.cfg ./
        sed -i 's%ubiquity/reboot boolean false%ubiquity/reboot boolean true%' ./project.cfg
        sed -i 's%ubiquity/poweroff boolean true%ubiquity/poweroff boolean false%' ./project.cfg
        mv project.cfg $temp_folder/preseed
        # replace $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/pack-fish.openssh-fossa --depth 1
        # replace $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-oobe --depth 1
        # copy from maas. TODO: make it to use from same source.
        mkdir -p $temp_folder/debs/main
        pushd $temp_folder/debs/main
        rm -rf maas_deps
        git clone --depth 1 -b maas-focal lp:~lyoncore-team/lyoncore/+git/somerville-maas-override maas_deps
        cd maas_deps
        git rev-parse --short HEAD
        rm -f maas-pkgs/oem-fix-misc-cnl-maas-helper*
        cd ..
        cp -r maas_deps/maas-pkgs/*.deb .
        find .
        popd
        # TODO: share this with MaaS to use a same source. (e.g. debian package)
        echo "#!/bin/bash
. /usr/share/volatile/common.sh
set -x
dpkg -i /cdrom/debs/main/*.deb
apt-get install -fy
" | tee 32-install-custom-pkgs.sh
        mkdir -p $temp_folder/scripts/chroot-scripts/os-post
        mv 32-install-custom-pkgs.sh $temp_folder/scripts/chroot-scripts/os-post
    else
        # get checkbox pkgs and prepare-checkbox
        # get pkgs to skip OOBE
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-no-secureboot --depth 1
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-storage-selecting --depth 1
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/pack-fish.openssh-fossa --depth 1
        $GIT clone https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/oem-fix-misc-cnl-skip-oobe --depth 1
    fi

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
UUID_OF_RECOVERY_PARTITION=\$(ls -l /dev/disk/by-uuid/ | grep vda2 | awk '{print \$9}')
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
        for folder in debs preseed scripts; do
            $SCP -r "$temp_folder/$folder" "$user_on_target"@"$target_ip":~/push_preseed || $SSH "$user_on_target"@"$target_ip" sudo rm -f push_preseed/SUCCSS_push_preseed
        done
    else
        for folder in pack-fish.openssh-fossa oem-fix-misc-cnl-no-secureboot oem-fix-misc-cnl-skip-oobe oem-fix-misc-cnl-skip-storage-selecting; do
            tar -C "$temp_folder"/$folder -zcvf "$temp_folder"/$folder.tar.gz .
            $SCP "$temp_folder/$folder".tar.gz "$user_on_target"@"$target_ip":~
            $SSH "$user_on_target"@"$target_ip" tar -C push_preseed -zxvf $folder.tar.gz || $SSH "$user_on_target"@"$target_ip" sudo rm -f push_preseed/SUCCSS_push_preseed
        done
    fi

    for folder in misc_for_automation; do
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

    if [ "${ubr}" == "yes" ]; then
        $SSH "$user_on_target"@"$target_ip" bash \$HOME/push_preseed/preseed/set_env_for_ubuntu_recovery || usage
    fi
    $SSH "$user_on_target"@"$target_ip" touch /tmp/SUCCSS_inject_preseed
}

inject_recovery_iso() {
    if [ -n "$local_iso" ]; then
        img_name="$(basename "$local_iso")"
        if [ -z "${img_name##*stella*}" ]; then
            ubr="yes"
        fi
        if [ "${ubr}" == "yes" ]; then
            rsync_opts="--exclude=efi --delete --temp-dir=/var/tmp/rsync"
        else
            rsync_opts="--exclude=factory/grub.cfg* --exclude=efi/boot \
--exclude=.disk/casper-uuid --exclude=.disk/info \
--exclude=.disk/info.recovery --exclude=efi.factory --delete \
--exclude=casper/filesystem.squashfs --temp-dir=/var/tmp/rsync"
        fi
        scp -o StrictHostKeyChecking=no "$local_iso" "$user_on_target"@"$target_ip":~/
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
        scp -o StrictHostKeyChecking=no "$temp_folder"/"$script_on_target_machine" "$user_on_target"@"$target_ip":~/
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" chmod +x "\$HOME/$script_on_target_machine"
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" "\$HOME/$script_on_target_machine"
        scp -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip":/tmp/SUCCSS_inject_recovery_iso "$temp_folder" || usage
    else
        img_jenkins_out_url="ftp://$jenkins_url/jenkins_host/jobs/$jenkins_job_for_iso/builds/$jenkins_job_build_no/archive/out"
        img_name="$(wget -q "$img_jenkins_out_url/" -O - | grep -o 'href=.*iso"' | awk -F/ '{print $NF}' | tr -d \")"
        pushd "$temp_folder" || usage
        wget "$img_jenkins_out_url/$img_name".md5sum
        md5sum -c "$img_name".md5sum || wget "$img_jenkins_out_url"/"$img_name" 2> /dev/null
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
    if [ "${ubr}" == "yes" ]; then
        echo GRUB_DEFAULT='"ubuntu-recovery restore"' | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        echo GRUB_TIMEOUT_STYLE=menu | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        echo GRUB_TIMEOUT=5 | $SSH "$user_on_target"@"$target_ip" -T "sudo tee -a /etc/default/grub.d/automatic-oem-config.cfg"
        $SSH "$user_on_target"@"$target_ip" sudo update-grub
        $SSH "$user_on_target"@"$target_ip" sudo reboot &
    else
        ssh -o StrictHostKeyChecking=no "$user_on_target"@"$target_ip" sudo dell-restore-system -y &
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
