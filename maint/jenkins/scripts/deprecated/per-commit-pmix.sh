#!/bin/bash

set -x

REMOTE_WS=$1
netmod=$2
provider=$3
compiler=$4
am=$5
direct=$6
config=$7
WORKSPACE=$8

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

cd $REMOTE_WS

./autogen.sh --with-autotools=$AUTOTOOLS_DIR

/bin/bash ${BUILD_SCRIPT} \
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
    -P pmix \
    -j "$CONFIG_EXTRA"
