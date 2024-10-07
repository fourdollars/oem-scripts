#!/bin/bash
#
# Script to generate dell embargo config and put to /etc/fwupd/remotes.d/ for accessing Dell embargo firmwares
#
TARGET_IPs=("$@")
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
CMD_TIMEOUT=10
TARGET_USER="ubuntu"
EMBARGO_CONF="dell-embargo.conf"

echo "Generate $EMBARGO_CONF"
printf "%s\n" "[fwupd Remote]" \
              "Enabled=true" \
              "Title=Embargoed for dell" \
              "#Keyring=gpg" \
              "MetadataURI=https://fwupd.org/downloads/firmware-c1255377a9c3465f605183b8b648e57a5202a890.xml.gz" \
              "ReportURI=https://fwupd.org/lvfs/firmware/report" \
              "OrderBefore=lvfs,fwupd" \
              "AutomaticReports=true" > "$EMBARGO_CONF"

for TARGET_IP in "${TARGET_IPs[@]}"; do
    # If DUT is offline, we timeout in 10 sec. and try the next one
    if timeout "$CMD_TIMEOUT" scp "${SSH_OPTS[@]}" "$EMBARGO_CONF" "$TARGET_USER@$TARGET_IP:/tmp"; then
        # shellcheck disable=SC2029
        ssh "${SSH_OPTS[@]}" "$TARGET_USER@$TARGET_IP" "sudo mv /tmp/$EMBARGO_CONF /etc/fwupd/remotes.d/" || true
        echo "Put the $EMBARGO_CONF to $TARGET_IP successfully"
    else
        echo "Failed to copy $EMBARGO_CONF to $TARGET_IP"
    fi
done

rm "$EMBARGO_CONF"