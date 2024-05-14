#!/bin/bash

exec 2>&1
set -euox pipefail

usage()
{
cat <<EOF
Usage:
    $0 [OPTIONS] <TARGET_IP 1> <TARGET_IP 2> ...
Options:
    -h|--help        The manual of the script
    --iso            ISO file path to be deployed on the target
    --url            URL link to deploy the ISO from internet
    -u|--user        The user of the target, default ubuntu
    -o|--timeout     The timeout for doing the deployment, default 3600 seconds
Examples:
    $0 -u ubuntu --iso /home/ubuntu/Downloads/somerville-noble-hwe-20240501-65.iso 10.42.0.161
    $0 -u ubuntu --url https://people.canonical.com/~kchsieh/images/somerville-noble-hwe-20240501-65.iso 10.42.0.161
EOF
}

if [ $# -lt 3 ]; then
    usage
    exit
fi

TARGET_USER="ubuntu"
TARGET_IPS=()
ISO_PATH=
ISO=
STORE_PART=""
TIMEOUT=3600
CONFIG_REPO_PATH="$HOME/.cache/oem-scripts/ubuntu-oem-image-builder"
CONFIG_REPO_REMOTE="git+ssh://$USER@git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/ubuntu-oem-image-builder"
URL_CACHE_PATH="$HOME/.cache/oem-scripts/images"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="ssh $SSH_OPTS"
SCP="scp $SSH_OPTS"

if [ ! -d "$HOME/.caceh/oem-scripts" ]; then
    mkdir -p "$HOME/.cache/oem-scripts"
fi

OPTS="$(getopt -o u:o: --long iso:,user:,timeout:,url: -n 'image-deploy.sh' -- "$@")"
eval set -- "${OPTS}"
while :; do
    case "$1" in
        ('-h'|'--help')
            usage
	    exit;;
        ('--url')
            ISO=$(basename "$2")
            if [ -f "$URL_CACHE_PATH/$ISO" ]; then
                echo "$ISO has been downloaded"
            else
                mkdir -p "$URL_CACHE_PATH" || true
                pushd "$URL_CACHE_PATH"
                if [[ "$2" =~ 10.131.50.220:8080 ]]; then
                    curl -nS -O "$2"
                else
                    curl -O "$2"
                fi
                popd
            fi
            ISO_PATH="$URL_CACHE_PATH/$ISO"
            shift 2;;
        ('--iso')
            ISO_PATH="$2"
	    ISO=$(basename "$ISO_PATH")
            shift 2;;
        ('-u'|'--user')
            TARGET_USER="$2"
	    shift 2;;
        ('-o'|'--timeout')
            TIMEOUT="$2"
            shift 2;;
	('--') shift; break ;;
	(*) break ;;
    esac
done

if [ ! -f "$ISO_PATH" ]; then
    echo "No designated ISO file"
    exit
fi

for addr in "$@";
do
    TARGET_IPS+=("$addr")
done


# Download config repo to local
if [ ! -d "$CONFIG_REPO_PATH" ]; then
    git -C "$HOME/.cache/oem-scripts" clone -b noble "$CONFIG_REPO_REMOTE"
else
    git -C "$CONFIG_REPO_PATH" pull
fi

for addr in "${TARGET_IPS[@]}";
do
    # Clear the knonw host
    ssh-keygen -f "/home/$USER/.ssh/known_hosts" -R "$addr"

    # Find the partitions
    while read -r name fstype mountpoint;
    do
        echo "$name,$fstype,$mountpoint"
        if [ "$fstype" = "ext4" ]; then
            if [ "$mountpoint" = "/home/$TARGET_USER" ] || [ "$mountpoint" = "/" ]; then
                STORE_PART="/dev/$name"
                break
            fi
        fi
    done < <($SSH "$TARGET_USER"@"$addr" -- lsblk -n -l -o NAME,FSTYPE,MOUNTPOINT)

    if [ -z "$STORE_PART" ]; then
        echo "Can't find partition to store ISO on target $addr"
        exit
    fi
    RESET_PART="${STORE_PART:0:-1}2"
    RESET_PARTUUID=$($SSH "$TARGET_USER"@"$addr" -- lsblk -n -o PARTUUID "$RESET_PART")
    EFI_PART="${STORE_PART:0:-1}1"

    # Copy ISO to the target
    $SCP "$ISO_PATH" "$TARGET_USER"@"$addr":/home/"$TARGET_USER"

    # Copy cloud-config redeploy to the target
    $SSH "$TARGET_USER"@"$addr" -- mkdir -p /home/"$TARGET_USER"/redeploy/cloud-configs/redeploy
    $SSH "$TARGET_USER"@"$addr" -- mkdir -p /home/"$TARGET_USER"/redeploy/cloud-configs/grub
    $SCP "$CONFIG_REPO_PATH"/alloem-init/cloud-configs/redeploy/meta-data "$TARGET_USER"@"$addr":/home/"$TARGET_USER"/redeploy/cloud-configs/redeploy/
    $SCP "$CONFIG_REPO_PATH"/alloem-init/cloud-configs/redeploy/user-data "$TARGET_USER"@"$addr":/home/"$TARGET_USER"/redeploy/cloud-configs/redeploy/
    $SCP "$CONFIG_REPO_PATH"/alloem-init/cloud-configs/grub/redeploy.cfg "$TARGET_USER"@"$addr":/home/"$TARGET_USER"/redeploy/cloud-configs/grub/redeploy.cfg

    # Umount the partitions
    MOUNT=$($SSH "$TARGET_USER"@"$addr" -- lsblk -n -o MOUNTPOINT "$RESET_PART")
    if [ -n "$MOUNT" ]; then
        $SSH "$TARGET_USER"@"$addr" -- sudo umount "$RESET_PART"
    fi
    MOUNT=$($SSH "$TARGET_USER"@"$addr" -- lsblk -n -o MOUNTPOINT "$EFI_PART")
    if [ -n "$MOUNT" ]; then
        $SSH "$TARGET_USER"@"$addr" -- sudo umount "$EFI_PART"
    fi

    # Format partitions
    $SSH "$TARGET_USER"@"$addr" -- sudo mkfs.vfat "$RESET_PART"
    $SSH "$TARGET_USER"@"$addr" -- sudo mkfs.vfat "$EFI_PART"

    # Mount ISO and reset partition
    $SSH "$TARGET_USER"@"$addr" -- mkdir -p /home/"$TARGET_USER"/iso || true
    $SSH "$TARGET_USER"@"$addr" -- mkdir -p /home/"$TARGET_USER"/reset || true
    $SSH "$TARGET_USER"@"$addr" -- sudo mount -o loop /home/"$TARGET_USER"/"$ISO" /home/"$TARGET_USER"/iso || true
    $SSH "$TARGET_USER"@"$addr" -- sudo mount "$RESET_PART" /home/"$TARGET_USER"/reset || true

    # Sync ISO to the reset partition
    $SSH "$TARGET_USER"@"$addr" -- sudo rsync -avP /home/"$TARGET_USER"/iso/ /home/"$TARGET_USER"/reset || true

    # Sync cloud-configs to the reset partition
    $SSH "$TARGET_USER"@"$addr" -- sudo mkdir -p /home/"$TARGET_USER"/reset/cloud-configs || true
    $SSH "$TARGET_USER"@"$addr" -- sudo cp -r /home/"$TARGET_USER"/redeploy/cloud-configs/redeploy/ /home/"$TARGET_USER"/reset/cloud-configs/
    $SSH "$TARGET_USER"@"$addr" -- sudo cp /home/"$TARGET_USER"/redeploy/cloud-configs/grub/redeploy.cfg /home/"$TARGET_USER"/reset/boot/grub/grub.cfg
    $SSH "$TARGET_USER"@"$addr" -- sudo sed -i "s/RP_PARTUUID/${RESET_PARTUUID}/" /home/"$TARGET_USER"/reset/boot/grub/grub.cfg

    # Reboot the target
    $SSH "$TARGET_USER"@"$addr" -- sudo reboot || true
done

# Clear the known hosts
for addr in "${TARGET_IPS[@]}";
do
    ssh-keygen -f "/home/$USER/.ssh/known_hosts" -R "$addr"
done

# Polling the targets
STARTED=("${TARGET_IPS[@]}")
finished=0
startTime=$(date +%s)
while :;
do
    sleep 180
    currentTime=$(date +%s)
    if [[ $((currentTime - startTime)) -gt $TIMEOUT ]]; then
        echo "Timeout is reached, deployment are not finished"
        break
    fi

    for addr in "${STARTED[@]}";
    do
        if $SSH "$TARGET_USER"@"$addr" -- exit; then
            finished=$((finished + 1))
        fi
    done

    if [ $finished -eq ${#TARGET_IPS[@]} ]; then
        echo "Deployment are done"
        break
    fi
done
