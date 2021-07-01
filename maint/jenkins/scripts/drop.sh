#!/bin/bash

set -x

REMOTE_WS=$1
provider=$2
compiler=$3
configs=$4
pmix=$5
WORKSPACE=$6
direct="auto"
force_am="noam"

JENKINS_DIR="$REMOTE_WS/maint/jenkins"
BUILD_SCRIPT_DIR="$JENKINS_DIR/scripts"
VERSION=drop$(<$JENKINS_DIR/drop_version)
release=$(<$JENKINS_DIR/release_version)
echo "DROP VERSION NUMBER: ${VERSION} RELEASE NUMBER: ${release}"
BUILD_SCRIPT="${BUILD_SCRIPT_DIR}/test-worker.sh"
TMP_ROOT="/tmp"
PRE="/state/partition1/home/sys_csr1/"
REL_WORKSPACE="${WORKSPACE#$PRE}"
fail=0
AUTOTOOLS_DIR="$HOME/software/autotools/bin"
OFI_DIR="/opt/intel/csr/ofi/$provider"
HWLOC_DIR="/opt/intel/csr"
NETMOD_OPTS=
run_tests="yes"
extra_compiler_args=""
extra_config_args=""
embedded=no
daos=yes
n_jobs=32
custom_version_string="${VERSION}_release${release}"
if [ $pmix = "pmix" ]; then
    NAME="mpich-ofi-$provider-$compiler-$configs-pmix-$VERSION"
else
    NAME="mpich-ofi-$provider-$compiler-$configs-$VERSION"
fi
INSTALL_DIR="/tmp/${NAME}/usr/mpi/${NAME}/"

if [ $provider != "" ]; then
    extra_config_args="${extra_config_args} --with-default-ofi-provider=${provider}"
fi

srun --chdir="$BUILD_SCRIPT_DIR" "$BUILD_SCRIPT_DIR/generate_drop_files.sh" "$REMOTE_WS" "$JENKINS_DIR" "$provider" "$compiler" "$configs" "$pmix"
srun --chdir="$BUILD_SCRIPT_DIR" cat "$REMOTE_WS/mpich.sh"

OFI_DIR="$OFI_DIR-dynamic"

# set json files paths
export MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE="${JENKINS_DIR}/json-files/CH4_coll_tuning.json"
export MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE="${JENKINS_DIR}/json-files/MPIR_Coll_tuning.json"
echo $MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE
echo $MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE

export LD_LIBRARY_PATH=$OFI_DIR/lib/:$LD_LIBRARY_PATH

srun --chdir="$REMOTE_WS" /bin/bash ${BUILD_SCRIPT} \
    -f $INSTALL_DIR \
    -h ${REMOTE_WS}/_build \
    -i ${OFI_DIR} \
    -c $compiler \
    -o $configs \
    -b drop \
    -s $direct \
    -p $provider \
    -m ${n_jobs} \
    -r $REL_WORKSPACE \
    -t 2.0 \
    -x $run_tests \
    -k $embedded \
    -d $force_am \
    -D $daos \
    -P $pmix \
    -y $custom_version_string \
    -j "$extra_config_args" \
    -e $extra_compiler_args

if [ $? != 0 ]; then
    fail=1
fi

if [ $fail = 0 ]; then
    srun mkdir -p $INSTALL_DIR/share/doc/mpich
    srun --chdir="$REMOTE_WS" install -m 0644 'COPYRIGHT' $INSTALL_DIR/share/doc/mpich
    srun --chdir="$REMOTE_WS" install -m 0644 'CHANGES' $INSTALL_DIR/share/doc/mpich
    srun --chdir="$REMOTE_WS" install -m 0644 README $INSTALL_DIR/share/doc/mpich
    srun --chdir="$REMOTE_WS" install -m 0644 README.envvar $INSTALL_DIR/share/doc/mpich
    srun mkdir -p $INSTALL_DIR/modulefiles/mpich
    srun cp -r  ${REMOTE_WS}/modulefiles/mpich/ $INSTALL_DIR/modulefiles/
    srun cp -r ${JENKINS_DIR}/json-files $INSTALL_DIR
    srun cp -r ${REMOTE_WS}/mpich.sh $INSTALL_DIR
    srun --chdir="/tmp" tar cjf $NAME.tar.bz2 $NAME
    srun --chdir="/tmp" rm -rf $INSTALL_DIR
    srun --chdir="/tmp" mkdir -p /home/sys_csr1/rpmbuild/{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
    srun --chdir="/tmp" mv $NAME.tar.bz2 /home/sys_csr1/rpmbuild/SOURCES/$NAME.tar.bz2
    srun --chdir="$WORKSPACE" mkdir -p maint/jenkins
    srun --chdir="$REMOTE_WS" cp $JENKINS_DIR/drop_version $WORKSPACE/maint/jenkins/drop_version
fi
