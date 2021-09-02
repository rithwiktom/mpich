#!/bin/bash

set -x

export job=$1
export INSTALL_DIR=$2
#export build_mpi=$3
export REMOTE_WS=$3 #This contains info of buid_mpi

# We are not changing these as a part of this test.
# This is useful to get correct names of the builds.
# This will also help in applying correct xfails.
provider=psm2
compiler=gnu
configs=debug
direct=auto
force_am=noam

JENKINS_DIR="${REMOTE_WS}/maint/jenkins"
BUILD_SCRIPT_DIR="${JENKINS_DIR}/scripts"

#set run paths
export OFI_DIR=/opt/intel/csr/ofi/${provider}-dynamic
export PATH=${INSTALL_DIR}/bin:$PATH
export LD_LIBRARY_PATH=${OFI_DIR}/lib:/opt/intel/csr/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=${INSTALL_DIR}/lib:$LD_LIBRARY_PATH
srun ls -lrt "${INSTALL_DIR}/bin"
srun ls -lrt "${INSTALL_DIR}/lib"

if [ ${compiler} == "gnu" ]; then
     if [ -f /opt/rh/devtoolset-7/enable ]; then
       source /opt/rh/devtoolset-7/enable
     elif [ -f /opt/rh/devtoolset-6/enable ]; then
       source /opt/rh/devtoolset-6/enable
     elif [ -f /opt/rh/devtoolset-4/enable ]; then
       source /opt/rh/devtoolset-4/enable
     elif [ -f /opt/rh/devtoolset-3/enable ]; then
       source /opt/rh/devtoolset-3/enable
     fi
fi

# set xfails here
xfail_file=${REMOTE_WS}/maint/jenkins/xfail.conf
srun --chdir="${REMOTE_WS}" chmod +x ${BUILD_SCRIPT_DIR}/set-xfail.sh
srun --chdir="${REMOTE_WS}" ${BUILD_SCRIPT_DIR}/set-xfail.sh -j rpm -c ${compiler} -o ${configs} -s ${direct} -m ${provider} -a ${force_am} -f ${xfail_file} -p nopmix

#srun --chdir="${REMOTE_WS}/test/mpi/" -N 1 make testing
srun --chdir="${REMOTE_WS}/test/mpi/" -N 1 ./runtests -srcdir=. -tests=testlist,testlist.dtp,testlist.cvar -mpiexec="${INSTALL_DIR}/bin/mpiexec" -xmlfile=summary.xml -tapfile=summary.tap -junitfile=summary.junit.xml
if [ $? != 0 ]; then
    fail=1
fi

exit $fail
