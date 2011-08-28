#!/bin/bash
#$1 path to modules dir
#TODO cross compiling for ARM
#set -x
RELEASE=$(uname -r)
#VERSION=linux-$(echo $RELEASE|cut -d '-' -f1)
BUILDPREFIX=$1
MODPASS=$2
BUILDDIR=${BUILDPREFIX}/${VERSION}/${MODPASS}
LIBMODULESDIR=lib/modules/${RELEASE}
DEBUGDIR=/usr/lib/debug
sudo make -C /${LIBMODULESDIR}/build CONFIG_DEBUG_INFO=y M=${BUILDDIR}
MODLIST=$(ls ${BUILDDIR}/*.ko)
#remove old links
for file in $MODLIST
do
	echo Processing $file
	sudo cp -a $file /${LIBMODULESDIR}/kernel/${MODPASS}/.
	sudo cp -a $file ${DEBUGDIR}/${LIBMODULESDIR}/kernel/${MODPASS}/.
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