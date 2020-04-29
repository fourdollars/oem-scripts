#!/bin/sh
# Canonical (C) 2012-2013
# FourDollars aka Shih-Yuan Lee <sylee@canonical.com>
# Rex Tsai <rex.tsai@canonical.com>

TARGET="$1"
NAME=$(basename $TARGET)
CMD=$2
OUTPUTDIR=${3-`pwd`}
if [ ! -f "$TARGET" ] || [ -z $CMD ] ; then
    echo "$0: image.[img|squashfs] [diff|tar|squashfs]"
    exit 0
fi

TMPDIR="$(mktemp -d)"
LOOPDIR="$(mktemp -d)"
DIFFDIR="$(mktemp -d)"
AUFSDIR="$(mktemp -d)"
if head $TARGET | file - | grep "x86 boot sector" ; then
    sudo mount -o ro,offset=512 $TARGET $TMPDIR
    sudo mount -r $TMPDIR/casper/filesystem.squashfs $LOOPDIR
    sudo mount -t aufs -o br:$DIFFDIR:$LOOPDIR none $AUFSDIR
    if file $AUFSDIR/bin/ls | grep ARM >/dev/null 2>&1; then
        sudo cp /usr/bin/qemu-arm-static $AUFSDIR/usr/bin/
    fi
else
    sudo mount -o ro $TARGET $LOOPDIR
    sudo mount -t aufs -o br:$DIFFDIR:$LOOPDIR none $AUFSDIR
    if file $AUFSDIR/bin/ls | grep ARM >/dev/null 2>&1; then
        sudo cp /usr/bin/qemu-arm-static $AUFSDIR/usr/bin/
    fi
fi

export LANG=C LANGUAGE=C

sudo chroot $AUFSDIR /bin/bash

if [ -f $AUFSDIR/usr/bin/qemu-arm-static ]; then
    sudo rm $AUFSDIR/usr/bin/qemu-arm-static
fi

# Generate diff tarball or diff or new squashfs for testing.
cd $DIFFDIR
case ${CMD} in
    "tar")
        sudo tar cJf ${OUTPUTDIR}/${NAME}.tar.xz *
        ;;
    "diff")
        exec 3> ${OUTPUTDIR}/$NAME.diff

        for file in $(sudo find -type f -print | grep -v './.wh..wh'); do
            if [ -f $LOOPDIR/$file ]; then
                a="$LOOPDIR/$file"
            else
                a='/dev/null'
            fi
            b="$DIFFDIR/$file"
            sudo diff -u $a $b | sed "s,$LOOPDIR/.,a," | sed "s,$DIFFDIR/.,b," >&3
        done
        ;;
    "squashfs")
        mksquashfs $AUFSDIR ${OUTPUTDIR}/$NAME.squashfs.new -info
        ;;
esac

sudo umount $AUFSDIR && rmdir $AUFSDIR
sudo umount $LOOPDIR && rmdir $LOOPDIR
sudo rm -fr $DIFFDIR

sudo umount $TMPDIR && rmdir $TMPDIR
