#!/bin/bash

set -x

export job=$1
export REMOTE_WS=$2

force_am="noam"
BUILD_SCRIPT_DIR="$REMOTE_WS/maint/jenkins/scripts"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/vci-test.sh"
TMP_ROOT="/tmp"
NAME="mpich-ofi-$configs-$direct-$force_am-$provider-$compiler-$job"
RPM_NAME="mpich-ofi-$provider-$compiler-$job"
PRE="/state/partition1/home/sys_csr1/"
REL_WORKSPACE="${WORKSPACE#$PRE}"
fail=0
INSTALL_DIR="/tmp/$NAME/usr/mpi/$RPM_NAME/"
AUTOTOOLS_DIR="$HOME/software/autotools/bin"
OFI_DIR="/opt/intel/csr/ofi/$provider"
HWLOC_DIR="/opt/intel/csr"
NETMOD_OPTS=
run_tests="yes"
config_extra=""
embedded=no
n_jobs=32
OFI_DIR="$OFI_DIR-dynamic"

# Special hack for thread testing
# Include xfails for multithreaded test cases
# It's not trivial to check the existance of remote mt_xfail*.conf.
# Simply try to concatenate, as it won't break the xfail file even
# if mt_xfail*.conf doesn't exist.
srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_common.conf >> maint/jenkins/xfail.conf'

srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
cmd="cat maint/jenkins/mt_xfail_${mt_model}.conf >> maint/jenkins/xfail.conf"
srun --chdir="$REMOTE_WS" bash -c "$cmd"

if [ "${nvci}" = "vci4" ]; then
    srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
    cmd="cat maint/jenkins/mt_xfail_vci4.conf >> maint/jenkins/xfail.conf"
    srun --chdir="$REMOTE_WS" bash -c "$cmd"
fi

srun --chdir="$REMOTE_WS" /bin/bash ${BUILD_SCRIPT} \
    -f $INSTALL_DIR \
    -h ${REMOTE_WS} \
    -i ${OFI_DIR} \
    -c $compiler \
    -o $configs \
    -b $job \
    -s $direct \
    -p $provider \
    -m ${n_jobs} \
    -r $REL_WORKSPACE \
    -t 2.0 \
    -x $run_tests \
    -k $embedded \
    -d $force_am \
    -M ${mt_model} \
    -V ${nvci} \
    -j "${config_extra}"

if [ $? != 0 ]; then
    fail=1
fi

# NOTE: If this filename changes, it also needs to be updated in the `nightly-test-vci` job configuration on jenkins
filename="warnings.vci-${provider}-${compiler}-${force_am}-${direct}-${configs}-${mt_model}-${nvci}.txt"
cp ${REL_WORKSPACE}/${filename} /home/sys_csr1/nightly-warnings/

exit $fail
