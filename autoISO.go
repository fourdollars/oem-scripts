// make a auto install OEM ISO from a base OEM ISO image.
// Usage: autoISO /path/to/oem-xxx.iso
// Copyright (C) 2021  Canonical Ltd.
// Author: Shengyao Xue <shengyao.xue@canonical.com>
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
)

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func main() {
	if !fileExists("/usr/bin/mksquashfs") {
		fmt.Println("Please install squashfs-tools package first.")
		os.Exit(-1)
	}
	if !fileExists("/usr/bin/genisoimage") {
		fmt.Println("Please install genisoimage package first.")
		os.Exit(-1)
	}

	extractOnly := flag.Bool("x", false, "extract the base ISO image only.")
	keepFolder := flag.Bool("k", false, "keep the temporary folder after the new image created.")
	sanityTest := flag.Bool("s", false, "add first boot sanity test.")
	flag.Parse()

	currentUser, err := user.Current()
	check(err)
	if currentUser.Username != "root" {
		fmt.Printf("This program requires superuser privileges, please run it as root.\n")
		os.Exit(-1)
	}
	var baseiso string
	if flag.NArg() == 1 {
		baseiso = filepath.Clean(flag.Arg(0))
	} else {
		fmt.Printf("Usage: autoISO [option] /path/to/oem-xxx.iso\n")
		fmt.Printf("    -h: help for options.\n")
		os.Exit(0)
	}

	parentDir, err := os.Getwd()
	check(err)
	fmt.Printf("autoISO started, the artifacts will be created in current working directory: %v\n", parentDir)
	fmt.Printf("This might take several minutes. Please wait...\n")
	//autoISODir, err := os.MkdirTemp(parentDir, "autoISO-*")
	autoISODir, err := ioutil.TempDir(parentDir, "autoISO-*")
	check(err)
	check(os.Chdir(autoISODir))
	check(os.Mkdir("iso", 0775))
	check(os.Mkdir("squash", 0775))
	cmd := exec.Command("mount", baseiso, "iso")
	cmd.Dir = autoISODir
	check(cmd.Run())
	cmd = exec.Command("mount", "iso/casper/filesystem.squashfs", "squash")
	check(cmd.Run())
	cmd = exec.Command("cp", "-a", "iso", "isorw")
	check(cmd.Run())
	cmd = exec.Command("cp", "-a", "squash", "squashrw")
	check(cmd.Run())
	cmd = exec.Command("umount", "squash")
	check(cmd.Run())
	cmd = exec.Command("umount", "iso")
	check(cmd.Run())
	if *extractOnly {
		fmt.Printf("autoISO extracted only.\n")
	} else {
		// oem-config
		check(os.Mkdir("squashrw/usr/lib/oem-config/pre-install", 0775))
		preseed := `#!/bin/bash
cat <<EOF | sudo debconf-communicate ubiquity
SET passwd/user-fullname	u
FSET passwd/user-fullname seen true
SET passwd/username	u
FSET passwd/username	seen true
SET passwd/user-password	u
FSET passwd/user-password	seen true
SET passwd/user-password-again	u
FSET passwd/user-password-again	seen true
SET passwd/auto-login	true
FSET passwd/auto-login	seen true
SET time/zone	Asia/Shanghai
FSET time/zone	seen true
EOF

cat <<EOF | sudo debconf-communicate keyboard-configuration
SET keyboard-configuration/xkb-keymap us
FSET keyboard-configuration/xkb-keymap seen true
SET keyboard-configuration/layoutcode us
FSET keyboard-configuration/layoutcode seen true
SET keyboard-configuration/layout	English (US)
FSET keyboard-configuration/layout	seen true
SET keyboard-configuration/variant	English (US)
FSET keyboard-configuration/variant	seen true
EOF
`
		//check(ioutil.WriteFile("squashrw/usr/lib/oem-config/pre-install/oobe-preseed", []byte(preseed), 0775))
		check(ioutil.WriteFile("squashrw/usr/lib/oem-config/pre-install/oobe-preseed", []byte(preseed), 0775))
		grub := "GRUB_CMDLINE_LINUX=$(echo $GRUB_CMDLINE_LINUX automatic-oem-config)\n"
		check(ioutil.WriteFile("squashrw/etc/default/grub.d/automatic-oem-config.cfg", []byte(grub), 0664))

		// sanity test
		if *sanityTest {
			oemDevFirstBoot := `#!/bin/bash

set -x

while true ; do
  sleep 10
  ping -c 3 8.8.8.8 && break # ideally wired network works, use it.
  sleep 10
  if [ -e /etc/oem-config-hack/connect-wifi ]; then
    bash /etc/oem-config-hack/connect-wifi
  else
    echo Wired network not working and wifi not available, Quit!
    bash
    exit
  fi
done

if ! dpkg-query -W prepare-checkbox-sanity; then
  sudo add-apt-repository -y ppa:checkbox-dev/ppa
  sudo apt install -y prepare-checkbox-sanity
  sudo reboot
  exit
fi

if [ -e ~/.config/autostart/oem-dev-firstboot.desktop ]; then
  rm ~/.config/autostart/oem-dev-firstboot.desktop
fi

checkbox-run-plan pc-sanity-smoke-test --checkbox-conf /home/u/.config/checkbox.conf -b

sleep 3

gio open ~/.local/share/checkbox-ng/submission_*.html

bash
`
			check(ioutil.WriteFile("squashrw/usr/bin/oem-dev-firstboot", []byte(oemDevFirstBoot), 0775))
			oemDevFirstBootAutoStart := `#!/bin/bash
set -x
mkdir -p "/home/$1/.config/autostart/"
cat > /home/$1/.config/autostart/oem-dev-firstboot.desktop << EOF
[Desktop Entry]
Version=1.0
Encoding=UTF-8
Name=Local Sanity
Type=Application
Terminal=true
Exec=/usr/bin/oem-dev-firstboot
Categories=System;Settings
EOF
cat > /home/$1/.config/checkbox.conf <<EOF
[environment]
ROUTERS = multiple
OPEN_N_SSID = ubuntu-cert-n-open
OPEN_BG_SSID = ubuntu-cert-bg-open
OPEN_AC_SSID = ubuntu-cert-ac-open
OPEN_AX_SSID = ubuntu-cert-ax-open
WPA_N_SSID = ubuntu-cert-n-wpa
WPA_BG_SSID = ubuntu-cert-bg-wpa
WPA_AC_SSID = ubuntu-cert-ac-wpa
WPA_AX_SSID = ubuntu-cert-ax-wpa
WPA_N_PSK = insecure
WPA_BG_PSK = insecure
WPA_AC_PSK = insecure
WPA_AX_PSK = insecure
SERVER_IPERF = 192.168.1.99
TEST_TARGET_IPERF = 192.168.1.99
BTDEVADDR = 34:13:E8:9A:52:12

# Transfer server
TRANSFER_SERVER = cdimage.ubuntu.com
EOF
touch "/home/$1/.config/gnome-initial-setup-done"
chown -R "$1.$1" "/home/u/.config"
`
			check(ioutil.WriteFile("squashrw/usr/bin/oem-dev-firstboot-autostart", []byte(oemDevFirstBootAutoStart), 0775))
			oemDevFirstBootPostInstall := `#!/bin/bash
set -x
/usr/bin/oem-dev-firstboot-autostart u
`
			check(ioutil.WriteFile("squashrw/usr/lib/oem-config/post-install/oem-dev-firstboot", []byte(oemDevFirstBootPostInstall), 0775))
		}
		// ubiquity
		ubiquity, err := ioutil.ReadFile("squashrw/usr/lib/ubiquity/bin/ubiquity")
		check(err)
		ubiquity = bytes.Replace(ubiquity, []byte("def run_oem_hooks():\n    \"\"\"Run hook scripts from /usr/lib/oem-config/post-install.\"\"\"\n    hookdir = '/usr/lib/oem-config/post-install'\n"), []byte("def run_oem_hooks(hookdir):\n    \"\"\"Run hook scripts from hookdir.\"\"\""), -1)
		ubiquity = bytes.Replace(ubiquity, []byte("if oem_config:\n        run_oem_hooks()"), []byte("if oem_config:\n        run_oem_hooks('/usr/lib/oem-config/post-install')"), -1)
		ubiquity = bytes.Replace(ubiquity, []byte("if args"), []byte("if oem_config:\n        run_oem_hooks('/usr/lib/oem-config/pre-install')\n\n    if args"), -1)
		check(ioutil.WriteFile("squashrw/usr/lib/ubiquity/bin/ubiquity", ubiquity, 0755))

		// recovery
		recovery, err := ioutil.ReadFile("squashrw/usr/lib/ubiquity/plugins/ubuntu-recovery.py")
		check(err)
		// check if this change already landed to ubuntu-recovery package (version >= 0.4.9~20.04ouagadougou22)
		if !bytes.Contains(recovery, []byte("'UBIQUITY_AUTOMATIC' in os.environ")) {
			recovery = bytes.Replace(recovery, []byte("os.path.exists(\"/cdrom/.oem/bypass_create_media\")"), []byte("os.path.exists(\"/cdrom/.oem/bypass_create_media\") or ('UBIQUITY_AUTOMATIC' in os.environ)"), -1)
			check(ioutil.WriteFile("squashrw/usr/lib/ubiquity/plugins/ubuntu-recovery.py", recovery, 0755))
		}

		// bootstrap
		bootstrap, err := ioutil.ReadFile("squashrw/usr/lib/ubiquity/plugins/ubuntu-bootstrap.py")
		check(err)
		bootstrap = bytes.Replace(bootstrap, []byte("gi.require_version('UDisks', '2.0')\n"), []byte("gi.require_version('UDisks', '2.0')\nfrom gi.repository import GLib\n"), -1)
		bootstrap = bytes.Replace(bootstrap, []byte("self.interactive_recovery.set_sensitive(False)\n                self.automated_recovery.set_sensitive(False)"), []byte("self.interactive_recovery.set_sensitive(False)\n                self.automated_recovery.set_sensitive(False)\n                if value == \"dev\" and stage == 1:\n                    self.automated_recovery.set_active(True)\n                    self.controller.allow_go_forward(True)\n                    GLib.timeout_add(5000, self.controller.go_forward)\n"), -1)
		bootstrap = bytes.Replace(bootstrap, []byte("elif rec_type == 'hdd' or rec_type == 'dev':"), []byte("elif rec_type == 'hdd' or (rec_type == 'dev' and self.stage == 2):"), -1)
		bootstrap = bytes.Replace(bootstrap, []byte("or rec_type == 'hdd' or rec_type == 'dev':"), []byte("or rec_type == 'hdd' or (rec_type == 'dev' and self.stage == 2):"), -1)
		bootstrap = bytes.Replace(bootstrap, []byte("rpconf.rec_type == \"factory\""), []byte("(rpconf.rec_type == \"factory\" or rpconf.rec_type == \"dev\")"), -1)
		check(ioutil.WriteFile("squashrw/usr/lib/ubiquity/plugins/ubuntu-bootstrap.py", bootstrap, 0755))

		// user ubuntu, reservation for MAAS, cloud init etc.
		uUbuntu := `#!/bin/bash
adduser --disabled-password --gecos "" ubuntu
adduser ubuntu sudo
`
		check(ioutil.WriteFile("squashrw/usr/lib/oem-config/post-install/u-ubuntu", []byte(uUbuntu), 0775))

		// gconf-modification
		gconfModification := `#!/bin/bash
cat <<EOF >> /usr/share/glib-2.0/schemas/certification.gschema.override
[org.gnome.settings-daemon.plugins.power]
idle-dim=false
#sleep-display-ac=0
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
[org.gnome.desktop.session]
idle-delay=0
[org.gnome.desktop.screensaver]
ubuntu-lock-on-suspend=false
lock-enabled=false
idle-activation-enabled=false
EOF

glib-compile-schemas /usr/share/glib-2.0/schemas
`
		check(ioutil.WriteFile("squashrw/usr/lib/oem-config/post-install/gconf-modification", []byte(gconfModification), 0775))

		// disable unattended update of APT
		oemDisableUattn := `#!/usr/bin/python3
import softwareproperties
from softwareproperties import SoftwareProperties
import os

# given
#  euid,eguid 1000,1000
#  ruid,rguid 0, 0
# we need to seteuid to 0 so we have permission.
os.seteuid(0)
os.setegid(0)

s = SoftwareProperties.SoftwareProperties()
s.set_update_automation_level(softwareproperties.UPDATE_MANUAL)

print("OK")
`
		check(ioutil.WriteFile("squashrw/usr/lib/oem-config/post-install/oem-disable-uattn", []byte(oemDisableUattn), 0775))

		// sudoers
		sudoers := "%sudo ALL=(ALL:ALL) NOPASSWD: ALL\n"
		check(ioutil.WriteFile("squashrw/etc/sudoers.d/oem-config-hack-nopwd", []byte(sudoers), 0664))

		// make new squashfs
		cmd = exec.Command("mksquashfs", "squashrw", "isorw/casper/filesystem.squashfs", "-noappend")
		check(cmd.Run())

		// projectCfg
		projectCfg, err := ioutil.ReadFile("isorw/preseed/project.cfg")
		check(err)
		// change recovery_type to dev
		projectCfg = bytes.Replace(projectCfg, []byte("# Hide"), []byte("ubiquity ubuntu-recovery/recovery_type string dev\n\n# Hide"), -1)
		// change poweroff to reboot
		projectCfg = bytes.Replace(projectCfg, []byte("ubiquity/reboot boolean false"), []byte("ubiquity/reboot boolean true"), -1)
		projectCfg = bytes.Replace(projectCfg, []byte("ubiquity/poweroff boolean true"), []byte("ubiquity/poweroff boolean false"), -1)
		check(ioutil.WriteFile("isorw/preseed/project.cfg", projectCfg, 0755))

		// make new ISO
		cmd = exec.Command("genisoimage", "-J", "-l", "-cache-inodes", "-allow-multidot", "-r", "-input-charset", "utf-8", "-eltorito-alt-boot", "-efi-boot", "boot/grub/efi.img", "-no-emul-boot", "-o", parentDir+"/"+filepath.Base(baseiso)+"."+filepath.Base(autoISODir)+".iso", "isorw")
		check(cmd.Run())

		if !*keepFolder {
			check(os.RemoveAll(autoISODir))
			fmt.Printf("autoISO done.\n")
		} else {
			fmt.Printf("autoISO done. Temporary folder %v keeped.\n", autoISODir)
		}
	}
}
