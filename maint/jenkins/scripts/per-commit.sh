#!/bin/bash

set -x

export REMOTE_WS=$1

BUILD_SCRIPT_DIR="$REMOTE_WS/maint/jenkins/scripts"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/test-worker.sh"
PRE="/state/partition1/home/sys_csr1"
REL_WORKSPACE="${WORKSPACE#$PRE}"
AUTOTOOLS_DIR="$HOME/software/autotools/bin"
OFI_DIR="/opt/intel/csr/ofi/${provider}"
HWLOC_DIR=/opt/intel/csr
embedded="no"
thread_cs=per-vci
mt_model=runtime
n_jobs=32

OFI_DIR="$OFI_DIR-dynamic"

# Check if there are instructions in the PR comment
echo ${ghprbCommentBody} > /tmp/jenkins_description
CONFIG_EXTRA=`/usr/bin/sed -n -e 's/^.*jenkins:config:\\\"\(.*\)\\\".*/\1/p' /tmp/jenkins_description`
echo "CONFIG_EXTRA: (${CONFIG_EXTRA})"

# Check if there are instructions in the PR body
if [ "x$CONFIG_EXTRA" = "x" ]; then
	echo "${ghprbPullDescription}" > /tmp/jenkins_description
	CONFIG_EXTRA=`/usr/bin/sed -n -e 's/^.*jenkins:config:\\\"\(.*\)\\\".*/\1/p' /tmp/jenkins_description`
	echo "CONFIG_EXTRA: (${CONFIG_EXTRA})"
fi
cat /tmp/jenkins_description
rm -f /tmp/jenkins_description

# Special hack for thread testing
if [ "$direct" = "thread" ]; then
    mt_model="handoff"
    direct="auto"

    # Test 4 vcis
    export MPIR_CVAR_CH4_NUM_VCIS=4
    export MPIR_CVAR_ASYNC_PROGRESS=1

    # Include xfails for multithreaded test cases
    if [ -f "maint/jenkins/mt_xfail_common.conf" ]; then
        echo "Appending mt_xfail_common.conf"
        srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
        srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_common.conf >> maint/jenkins/xfail.conf'
    fi
    if [ -f "maint/jenkins/mt_xfail_vci4.conf" ]; then
        echo "Appending mt_xfail_vci4.conf"
        srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
        srun --chdir="$REMOTE_WS" bash -c 'cat maint/jenkins/mt_xfail_vci4.conf >> maint/jenkins/xfail.conf'
    fi
    if [ -f "maint/jenkins/mt_xfail_${mt_model}.conf" ]; then
        echo "Appending mt_xfail_${mt_model}.conf"
        srun --chdir="$REMOTE_WS" bash -c "echo  '' >> maint/jenkins/xfail.conf"
        cmd="cat maint/jenkins/mt_xfail_${mt_model}.conf >> maint/jenkins/xfail.conf"
        srun --chdir="$REMOTE_WS" bash -c "$cmd"
    fi
elif [ "$am" = "force-am-enabled" ]; then
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

srun --chdir="$REMOTE_WS" ./autogen.sh --with-autotools=$AUTOTOOLS_DIR

srun --chdir="$REMOTE_WS" /bin/bash ${BUILD_SCRIPT} \
    -h ${REMOTE_WS}/_build \
    -i $OFI_DIR \
    -c $compiler \
    -o $config \
    -d $am \
    -b per-commit \
    -s $direct \
    -p ${provider} \
    -l ${thread_cs} \
    -m ${n_jobs} \
    -r $REL_WORKSPACE \
    -t 2.0 \
    -x yes \
    -k $embedded \
    -M ${mt_model} \
    -j "$CONFIG_EXTRA"
