#!/bin/bash

set -ex

AUTOTOOLS_DIR="/usr/bin"
TARBALL="mpich-integration.tar.bz2"

git submodule update --init --recursive

./autogen.sh --with-autotools=$AUTOTOOLS_DIR --without-ucx | tee a.txt

tar --exclude=${TARBALL} -cjf ${TARBALL} *

mv ${TARBALL} /tmp/${TARBALL}
