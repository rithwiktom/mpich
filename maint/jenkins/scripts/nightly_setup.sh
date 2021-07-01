#!/bin/bash

set -ex

AUTOTOOLS_DIR="/opt/intel/csr/bin"
TARBALL="mpich-integration.tar.bz2"

git submodule update --init --recursive

./autogen.sh --with-autotools=$AUTOTOOLS_DIR --without-ucx | tee a.txt

tar --exclude=${TARBALL} -cjf ${TARBALL} *

mv ${TARBALL} /tmp/${TARBALL}

# This script will run on one of the two headnoes, but we want the result to be available on both,
# so copy to the other one.
if [ "$(hostname -s)" == "angpc01" ]; then
    scp /tmp/${TARBALL} anccskl32.an.intel.com:/tmp/${TARBALL}
    scp /tmp/${TARBALL} anfedclx8.an.intel.com:/tmp/${TARBALL}
elif [ "$(hostname -s)" == "anfedclx8" ]; then
    scp /tmp/${TARBALL} anccskl32.an.intel.com:/tmp/${TARBALL}
    scp /tmp/${TARBALL} angpc01.an.intel.com:/tmp/${TARBALL}
else
    scp /tmp/${TARBALL} angpc01.an.intel.com:/tmp/${TARBALL}
    scp /tmp/${TARBALL} anfedclx8.an.intel.com:/tmp/${TARBALL}
fi
