#!/bin/bash
# Build modules and setup them for use with systemtap
#
# PARAMETERS:
# $1 path to the top of the kernel source tree, like /build/buildd/linux-2.6.35
# $2 relative path to the module dir, like sound/pci/hda
#
# TODO: verify with linux source not in /build/buildd
# TODO: cross compiling for ARM
#set -x


USAGE(){
    echo -e "\nUsage: $(basename $0) ABSOLUTE_PASS_TO_THE_TOP_OF_KERNEL_TREE REATIVE_PASS_TO_MODULES_DIR\n\n You don't have to have the whole kernel tree. Examples:"
    echo -e "$(basename $0) /build/buildd/linux-2.6.35 sound/pci/hda"
    echo -e "$(basename $0) `pwd` sound/pci/hda\n"
}
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ $# -lt 2 ]] ; then
    USAGE; exit 1
fi
RELEASE=$(uname -r)
#VERSION=linux-$(echo $RELEASE|cut -d '-' -f1)
BUILDPREFIX=$1
MODPASS=$2
BUILDDIR=${BUILDPREFIX}/${MODPASS}
LIBMODULESDIR=lib/modules/${RELEASE}
DEBUGDIR=/usr/lib/debug
sudo make -C /${LIBMODULESDIR}/build CONFIG_DEBUG_KERNEL=y CONFIG_KPROBES=y CONFIG_DEBUG_FS=y CONFIG_RELAY=y CONFIG_DEBUG_INFO=y M=${BUILDDIR}
MODLIST=$(ls ${BUILDDIR}/*.ko)

#remove old links, create new ones, update debug information

sudo mkdir -p /${LIBMODULESDIR}/kernel/${MODPASS}
sudo mkdir -p ${DEBUGDIR}/${LIBMODULESDIR}/kernel/${MODPASS}
for file in $MODLIST
do
	echo Processing $file
	sudo cp -av $file /${LIBMODULESDIR}/kernel/${MODPASS}/.
	bnf=$(basename $file)
	#ls -l /${LIBMODULESDIR}/updates/dkms/$bnf
	if [ -f /${LIBMODULESDIR}/updates/dkms/$bnf ]; then
	    sudo cp -av $file /${LIBMODULESDIR}/updates/dkms/.
	fi
	sudo cp -av $file ${DEBUGDIR}/${LIBMODULESDIR}/kernel/${MODPASS}/.

	#cleanup links to old module
	sudo find ${DEBUGDIR}/.build-id -lname *$(basename $file) -exec sudo rm -rf '{}' \;
	#setup new links        
	buildid=`eu-readelf -n $file| grep Build.ID: | awk '{print $3}'`
        dir=`echo $buildid | cut -c1-2`
        fn=`echo $buildid | cut -c3-`
        sudo mkdir -p ${DEBUGDIR}/.build-id/$dir
        sudo ln -s $file ${DEBUGDIR}/.build-id/$dir/$fn
        sudo ln -s $file ${DEBUGDIR}/.build-id/$dir/${fn}.debug
done
