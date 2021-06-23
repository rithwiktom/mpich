#!/bin/bash

set -ex

AUTOTOOLS_DIR="/home/sys_csr1/software/autotools/bin"
TARBALL="mpich-drops.tar.bz2"

while getopts ":a" opt; do
    case "$opt" in
        a)
            AUTOTOOLS_DIR=$OPTARG ;;
    esac
done

#Clear out RPM sources directory
rm -f /home/sys_csr1/rpmbuild/SOURCES/*$provider*drop*bz2

git submodule update --init --recursive
./autogen.sh --without-ucx --with-autotools=$AUTOTOOLS_DIR | tee a.txt

tar --exclude=${TARBALL} -cjf ${TARBALL} *

mv ${TARBALL} /tmp/${TARBALL}
