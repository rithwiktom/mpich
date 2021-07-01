#!/bin/bash

set -x

export job=$1
export REMOTE_WS=$2

BUILD_SCRIPT_DIR="$REMOTE_WS/maint/jenkins/scripts"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/test-worker.sh"
TMP_ROOT="/tmp"
NAME="mpich-ofi-$configs-$direct-$force_am-$provider-$compiler-$job"
RPM_NAME="mpich-ofi-$provider-$compiler-$configs-$job"
PRE="/state/partition1/home/nuser07/"
REL_WORKSPACE="${WORKSPACE#$PRE}"
fail=0
INSTALL_DIR="/tmp/$NAME/usr/mpi/$RPM_NAME/"

# Use system autotools due to perl versioning issues with help2man
AUTOTOOLS_DIR="/usr/bin"

# Local install of OFI
OFI_DIR="${HOME}/software/ofi/${provider}"

neo_dir="/home/puser42/neo/2020.10.05"
ze_dir="/home/puser42/neo/2020.10.05"
xpmem_dir="/opt/xpmem/git20200606"
ze_native="dg1"
BUILD_A20="yes"

NETMOD_OPTS=
run_tests="yes"
config_extra=""
embedded=yes
thread_cs=per-vci
mt_model=runtime
n_jobs=32

if [ "$configs" = "default" -a "$force_am" = "noam" -a "$direct" = "auto" ]; then
   if [ "$provider" = "psm2" -o "$provider" = "sockets" ]; then
      echo "Setting paths correctly for RPM Build script."
      NAME=${RPM_NAME}
      INSTALL_DIR="/tmp/$NAME/usr/mpi/$RPM_NAME"
   fi
fi

OFI_DIR="$OFI_DIR-dynamic"

# Special hack for thread testing
if [ "$direct" = "thread" ]; then
    direct="auto"
    mt_model="handoff"

    # Test 4 vcis
    export MPIR_CVAR_CH4_NUM_VCIS=4
    export MPIR_CVAR_ASYNC_PROGRESS=1

    # Include xfails for multithreaded test cases
    # It's not trivial to check the existance of remote mt_xfail*.conf.
    # Simply try to concatenate, as it won't break the xfail file even
    # if mt_xfail*.conf doesn't exist.
    srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
    srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_common.conf >> maint/jenkins/xfail.conf'
    srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_vci4.conf >> maint/jenkins/xfail.conf'

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
    -B $BUILD_A20 \
    -f $INSTALL_DIR \
    -h ${REMOTE_WS}/_build \
    -i ${OFI_DIR} \
    -c $compiler \
    -o $configs \
    -b $job \
    -s $direct \
    -p $provider \
    -l ${thread_cs} \
    -m ${n_jobs} \
    -N $neo_dir \
    -r $REL_WORKSPACE \
    -t 8.0 \
    -x $run_tests \
    -k $embedded \
    -d $force_am \
    -M ${mt_model} \
    -X $xpmem_dir \
    -Y $ze_native \
    -Z $ze_dir \
    -G $test \
    -z "-L$neo_dir/lib64" \
    -j "${config_extra}"

if [ $? != 0 ]; then
    fail=1
fi

${BUILD_SCRIPT_DIR}/check_warnings.sh \
    ${provider}-${compiler}-${force_am}-${direct}-${configs} \
    ${REL_WORKSPACE} \
    ${REL_WORKSPACE}/test/mpi/summary.junit.xml \
    "nuser07"

filename="warnings.${provider}-${compiler}-${force_am}-${direct}-${configs}.txt"
cp ${REL_WORKSPACE}/${filename} /home/nuser07/nightly-warnings/

exit $fail
