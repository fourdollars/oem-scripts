#!/bin/sh

NAME='live-build-image-chroot'
TARGET="$1"

[ ! -f "$TARGET" ] && exit 0

exec 3>$NAME.diff

TMPDIR="$(mktemp -d)"
if echo $TARGET | grep img$ ; then
    sudo mount -o ro,offset=512 $TARGET $TMPDIR
else
    sudo mount -o ro $TARGET $TMPDIR
fi

if [ -f $TMPDIR/casper/filesystem.squashfs ]; then
    LOOPDIR="$(mktemp -d)"
    sudo mount -r $TMPDIR/casper/filesystem.squashfs $LOOPDIR
    DIFFDIR="$(mktemp -d)"
    AUFSDIR="$(mktemp -d)"
    sudo mount -t aufs -o br:$DIFFDIR:$LOOPDIR none $AUFSDIR
    if file $AUFSDIR/bin/ls | grep ARM >/dev/null 2>&1; then
        ARM="1"
        sudo cp /usr/bin/qemu-arm-static $AUFSDIR/usr/bin/
    fi
    cd $AUFSDIR
else
    cd $TMPDIR
fi

export LANG=C LANGUAGE=C
sudo cp /etc/resolv.conf $AUFSDIR/etc/

sudo chroot $AUFSDIR /bin/bash
cd -

if [ -f $TMPDIR/casper/filesystem.squashfs ]; then
    if [ -f $AUFSDIR/usr/bin/qemu-arm-static ]; then
        sudo rm $AUFSDIR/usr/bin/qemu-arm-static
    fi
    sudo umount $AUFSDIR && rmdir $AUFSDIR
    cd $DIFFDIR
    if echo $* | grep tar >/dev/null 2>&1; then
        sudo tar cJf $OLDPWD/$NAME.tar.xz *
    fi
    if echo $* | grep diff >/dev/null 2>&1; then
        for file in $(sudo find -type f -print | grep -v './.wh..wh' | grep -v 'resolv.conf'); do
            if [ -f $LOOPDIR/$file ]; then
                a="$LOOPDIR/$file"
            else
                a='/dev/null'
            fi
            b="$DIFFDIR/$file"
            sudo diff -u $a $b | sed "s,$LOOPDIR/.,a," | sed "s,$DIFFDIR/.,b," >&3
        done
    fi
    cd -
    sudo umount $LOOPDIR && rmdir $LOOPDIR
    sudo rm -fr $DIFFDIR
fi

sudo umount $TMPDIR && rmdir $TMPDIR