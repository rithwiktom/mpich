#!/bin/bash

set -x

export job=$1

BUILD_SCRIPT_DIR="$WORKSPACE/maint/jenkins/scripts"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/test-worker.sh"
TMP_ROOT="/tmp"
NAME="mpich-ofi-$configs-$direct-$force_am-$provider-$compiler"
PRE="/state/partition1/home/sys_csr1/"
REL_WORKSPACE="${WORKSPACE#$PRE}"
fail=0
INSTALL_DIR="/home/sys_csr1/$NAME/"
AUTOTOOLS_DIR="$HOME/software/autotools/bin"
OFI_DIR="/opt/intel/csr/ofi/$provider"
HWLOC_DIR="/opt/intel/csr"
NETMOD_OPTS=
run_tests="no"
build_tests="yes"
config_extra=""
embedded=no
thread_cs=per-vci
mt_model=runtime
n_jobs=32
MPICH_CONFIG="mpich-nightly-integration-build-$configs-$direct-$force_am-$provider-$compiler"
TARBALL="${MPICH_CONFIG}.tar.bz2"

#if [ "$configs" = "default" -a "$force_am" = "noam" -a "$direct" = "auto" ]; then
#   if [ "$provider" = "psm2" -o "$provider" = "sockets" ]; then
#      echo "Setting paths correctly for RPM Build script."
#      NAME=${RPM_NAME}
#      INSTALL_DIR="/home/sys_csr1/$NAME"
#   fi
#fi

OFI_DIR="$OFI_DIR-dynamic"

srun --chdir="$WORKSPACE" /bin/bash ${BUILD_SCRIPT} \
    -A $build_tests \
    -f $INSTALL_DIR \
    -h ${WORKSPACE} \
    -i ${OFI_DIR} \
    -c $compiler \
    -o $configs \
    -b ${job} \
    -s $direct \
    -p $provider \
    -l ${thread_cs} \
    -m ${n_jobs} \
    -r $REL_WORKSPACE \
    -t 2.0 \
    -x $run_tests \
    -k $embedded \
    -d $force_am \
    -M ${mt_model} \
    -j "${config_extra}"

if [ $? != 0 ]; then
    fail=1
fi

tar --exclude=${TARBALL} --exclude=mpich-integration.tar.bz2 -cjf ${TARBALL} *

exit $fail
