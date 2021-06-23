#!/bin/bash

set -x

export job=$1
export REMOTE_WS=$2

BUILD_SCRIPT_DIR="$REMOTE_WS/maint/jenkins/scripts"
BUILD_SCRIPT="$BUILD_SCRIPT_DIR/test-worker.sh"
NAME="mpich-ofi-$configs-$direct-$force_am-$provider-$compiler"
INSTALL_DIR="/home/sys_csr1/$NAME"
build_tests="no"
build_mpich="no"
run_tests="yes"
embedded="no"
thread_cs=per-vci
PRE="/state/partition1/home/sys_csr1/"
REL_WORKSPACE="${WORKSPACE#$PRE}"
mt_model="runtime"
config_extra=""
OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"

# Add the install from integration-build-setup to the paths
export PATH=${INSTALL_DIR}/bin:$PATH
export LD_LIBRARY_PATH=${INSTALL_DIR}/lib:$LD_LIBRARY_PATH

# Special hack for thread testing
if [ "$direct" = "thread" ]; then
    direct="auto"
    mt_model="trylock"

    # Include xfails for multithreaded test cases
    # It's not trivial to check the existance of remote mt_xfail*.conf.
    # Simply try to concatenate, as it won't break the xfail file even
    # if mt_xfail*.conf doesn't exist.
    srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
    srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_common.conf >> maint/jenkins/xfail.conf'

    srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
    cmd="cat maint/jenkins/mt_xfail_${mt_model}.conf >> maint/jenkins/xfail.conf"
    srun --chdir="$REMOTE_WS" bash -c "$cmd"
elif [ "$force_am" = "force-am-enabled" ]; then
    # For now we use the global lock model for force-am-enabled for several reasons:
    # 1. we are not fully confident that AM path is thread safe
    # 2. it is for basic functionality checking only, we are not giving it to
    #    external people e.g. Dudley
    # 3. It is good to keep the global lock builds to make sure we didn't break
    #    anything there (at least it builds), especially given that Argonne's default
    #    is still global CS
    thread_cs="global"
    mt_model="direct"
fi

srun --chdir="$REMOTE_WS" /bin/bash ${BUILD_SCRIPT} \
    -A $build_tests \
    -q $build_mpich \
    -f $INSTALL_DIR \
    -h ${REMOTE_WS} \
    -i ${OFI_DIR} \
    -c $compiler \
    -o $configs \
    -b ${job} \
    -s $direct \
    -p $provider \
    -l ${thread_cs} \
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

exit $fail
