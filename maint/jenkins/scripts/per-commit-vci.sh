#!/bin/bash

set -x

export REMOTE_WS=$1

BUILD_SCRIPT_DIR="$REMOTE_WS/maint/jenkins/scripts"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/vci-test.sh"
TMP_ROOT="/tmp"
PRE="/state/partition1/home/sys_csr1"
REL_WORKSPACE="${WORKSPACE#$PRE}"
AUTOTOOLS_DIR="$HOME/software/autotools/bin"
OFI_DIR="/opt/intel/csr/ofi/${provider}"
n_jobs=48
embedded=no

if [ "$provider" = "psm2" ]; then
    OFI_DIR="$OFI_DIR-dynamic"
elif [ "$provider" = "opa1x" -a "$configs" = "opt" ]; then
    OFI_DIR="$OFI_DIR-direct"
    embedded=no
elif [ "$provider" = "opa1x" ]; then
    OFI_DIR="$OFI_DIR-direct"
elif [ "$provider" != "psm" -a "$configs" = "opt" ]; then
    OFI_DIR="$OFI_DIR-direct"
else
    OFI_DIR="$OFI_DIR-dynamic"
fi

# Check if there are instructions in the PR comment
echo ${GITHUB_PR_COMMENT_BODY} > /tmp/jenkins_description
CONFIG_EXTRA=`/usr/bin/sed -n -e 's/^.*jenkins:config:\\\"\(.*\)\\\".*/\1/p' /tmp/jenkins_description`
echo "CONFIG_EXTRA: (${CONFIG_EXTRA})"

# Check if there are instructions in the PR body
if [ "x$CONFIG_EXTRA" = "x" ]; then
    echo "${GITHUB_PR_BODY}" > /tmp/jenkins_description
    CONFIG_EXTRA=`/usr/bin/sed -n -e 's/^.*jenkins:config:\\\"\(.*\)\\\".*/\1/p' /tmp/jenkins_description`
    echo "CONFIG_EXTRA: (${CONFIG_EXTRA})"
fi
cat /tmp/jenkins_description
rm -f /tmp/jenkins_description

set -xe

srun --chdir="$REMOTE_WS" ./autogen.sh --with-autotools=$AUTOTOOLS_DIR

srun --chdir="$REMOTE_WS" /bin/bash ${BUILD_SCRIPT} \
    -h ${REMOTE_WS}/_build \
    -i $OFI_DIR \
    -c $compiler \
    -o $config \
    -s $direct \
    -p ${provider} \
    -m ${n_jobs} \
    -r $REL_WORKSPACE \
    -t 2.0 \
    -x yes \
    -k $embedded \
    -M $mt \
    -V $vci \
    -Y $async \
    -j "$CONFIG_EXTRA"

${BUILD_SCRIPT_DIR}/check_warnings.sh \
    "vci-${provider}-${compiler}-noam-${direct}-${config}-${mt}-${vci}" \
    ${REL_WORKSPACE} \
    ${REL_WORKSPACE}/test/mpi/summary.junit.xml \
    "sys_csr1"
