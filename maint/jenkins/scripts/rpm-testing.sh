#!/bin/bash

set -x

. ~/.bashrc

job=$1
nodes=$2
version=$3
release=$4
provider=$5
compiler=$6
configs=$7
pmix=$8
flavor=${9}
testgpu=${10}
WORKSPACE=${11}
direct=auto
force_am=noam

MPI_DIR=""
ze_dir=""
if [ "$flavor" == "gpu" ]; then
    ze_dir="/usr"
fi

pmix_string=""
if [ "$pmix" == "pmix" ]; then
    pmix_string="-pmix"
fi

flavor_string=""
if [ "$flavor" != "regular" ]; then
    flavor_string="-${flavor}"
fi

if [ "$flavor" == "gpu" ]; then
    config_opts="--with-ze=${ze_dir}"
fi

RPM="mpich-ofi-${provider}-${compiler}-${configs}${pmix_string}${flavor_string}-${job}"
MPI=mpich-ofi-${provider}-${compiler}-${configs}${pmix_string}${flavor_string}-${job}

if [ "${job}" == "nightly" ]; then
    RPM="${RPM}-`date +"%Y.%m.%d"`-1.x86_64"
else
    RPM="${RPM}-${version}-${release}.x86_64"
fi

export http_proxy=http://proxy-us.intel.com:911
export https_proxy=https://proxy-us.intel.com:911
export no_proxy="127.0.0.1, localhost, .intel.com"
export MPITEST_TIMEOUT_MULTIPLIER=2.0

JENKINS_DIR="$WORKSPACE/maint/jenkins"
BUILD_SCRIPT_DIR="$JENKINS_DIR/scripts"
if [ "${flavor}" != "gpu" ]; then
    OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"
else
    if [ "${provider}" == "psm3" ]; then
        OFI_DIR="/home/sys_csr1/software/libfabric/psm3-dynamic"
    else
      if [ -d "/opt/intel/csr/ofi/sockets-dynamic" ]; then
          OFI_DIR="/opt/intel/csr/ofi/sockets-dynamic"
      else
          OFI_DIR="/home/sys_csr1/software/libfabric/sockets"
      fi
    fi
fi
if [ "${provider}" == "all" ]; then
    if [ -d "/opt/intel/csr/ofi/sockets-dynamic" ]; then
        OFI_DIR="/opt/intel/csr/ofi/sockets-dynamic"
    else
        OFI_DIR="/home/sys_csr1/software/libfabric/sockets"
    fi
fi

DAOS_INSTALL_DIR="/opt/daos-34"
pmix_dir="/opt/pmix-4.2.2"
prte_dir="/opt/prrte-3.0.0"
hwloc_dir="/opt/hwloc-2.8.0"

count=1
#while [[ "$is_there" != 0 && "$count" -lt 10 ]]; do
#   if [ "${job}" == "nightly" ]; then
#       cp -f ${RPM_DIR}/$RPM.rpm ${WORKSPACE}/
#       is_there=$?
#       (( count++ ))
#   else
#       exit 1
#   fi
#done

rpm -qpR ${WORKSPACE}/$RPM.rpm

set -e
if [ "$flavor" == "gpu" ]; then
    # Boris has default MPICH installed. We need to unload it from environment to use our latest build.
    module unload mpich
    set +e
    rpm --initdb --dbpath /tmp/rpmdb
    rpm --dbpath /tmp/rpmdb --nodeps -ihv --prefix /tmp/inst ${WORKSPACE}/$RPM.rpm
    set -e
else
    sudo rpm -Uvh --force ${WORKSPACE}/$RPM.rpm --nodeps
fi

if [ "$nodes" -gt "1" ]; then
    if [ "$flavor" == "gpu" ]; then
        srun -N 1 -n 1 -r 1 $BUILD_SCRIPT_DIR/install_drop_rpm.sh 0 ${WORKSPACE}/$RPM.rpm
    else
    	srun -N 1 -n 1 -r 1 sudo rpm -Uvh --force ${WORKSPACE}/$RPM.rpm --nodeps
    fi
fi

set +e

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
elif [ ${compiler} == "icc" ]; then
          if [ -f /opt/rh/devtoolset-7/enable ]; then
              source /opt/rh/devtoolset-7/enable
          elif [ -f /opt/rh/devtoolset-6/enable ]; then
              source /opt/rh/devtoolset-6/enable
          elif [ -f /opt/rh/devtoolset-4/enable ]; then
              source /opt/rh/devtoolset-4/enable
          elif [ -f /opt/rh/devtoolset-3/enable ]; then
              source /opt/rh/devtoolset-3/enable
          fi
          # Look for a specific version here to avoid using the 2019.2.x version on anccskl32
          # which has problems with the C++ compiler
          if [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ]; then
              . /opt/intel/oneapi/compiler/latest/env/vars.sh intel64
              # Starting ICC2019 update 2, FI_PROVIDER_PATH is set to
              # /opt/intel/compilers_and_libraries_2019.4.243/linux/mpi/intel64/libfabric/lib/prov
              # We unset it because we dont want the provider to come from this location.
              unset FI_PROVIDER_PATH
          fi

fi


# First generate everything and copy it to a tmp workspace
#cd $BUILD_SCRIPT_DIR
#/bin/bash "$BUILD_SCRIPT_DIR/generate_drop_files.sh" "$WORKSPACE" "$JENKINS_DIR" "$provider" "$compiler" "$configs" "$pmix"
#cat "$WORKSPACE/mpich.sh"
#cd -
# Make sure module alias is setup
. /opt/ohpc/admin/lmod/lmod/init/bash >/dev/null
# check env by using module
if [ "$flavor" == "gpu" ]; then
    module use /tmp/inst/modulefiles/
    MPI_DIR="/tmp/inst/${MPI}"
else
    module use /usr/mpi/modulefiles/
    MPI_DIR="/usr/mpi/${MPI}"
fi

# Need to set FI_PROVIDER after loading the module file, because the modulefile unsets FI_PROVIDER
if [ ${provider} == "sockets" ]; then
    export FI_PROVIDER=sockets
elif [ ${provider} == "all" -o "${provider}" == "cxi" ]; then
    export FI_PROVIDER=cxi
elif [ ${provider} == "psm3" ]; then
    export FI_PROVIDER=psm3
    export PSM3_MULTI_EP=1
fi

if [ "$compiler" == "icc" ]; then
    if [ -d /opt/old_opt/intel/inteloneapi/compiler/latest/linux/bin/intel64 ]; then
        export PATH=/opt/old_opt/intel/inteloneapi/compiler/latest/linux/bin/intel64/:${PATH#*/mpi/intel64/bin:}:/bin
        export LD_LIBRARY_PATH=/opt/old_opt/intel/inteloneapi/compiler/latest/linux/compiler/lib/intel64_lin/:${LD_LIBRARY_PATH#*/mpi/intel64/lib:}
    elif [ -d /opt/intel/inteloneapi/compiler ]; then
        export PATH=/opt/intel/inteloneapi/compiler/latest/linux/bin/intel64/:${PATH#*/mpi/intel64/bin:}:/bin
        export LD_LIBRARY_PATH=/opt/intel/inteloneapi/compiler/latest/linux/compiler/lib/intel64_lin/:${LD_LIBRARY_PATH#*/mpi/intel64/lib:}
    elif [ -d /opt/intel/oneapi/compiler ]; then
        export PATH=/opt/intel/oneapi/compiler/latest/linux/bin/intel64/:${PATH#*/mpi/intel64/bin:}:/bin
        export LD_LIBRARY_PATH=/opt/intel/oneapi/compiler/latest/linux/compiler/lib/intel64_lin/:${LD_LIBRARY_PATH#*/mpi/intel64/lib:}
    else
        module load intel
    fi
fi

if [ "$configs" = "debug" ]; then
    module load mpich/${compiler}-${provider}-${configs}${pmix_string}${flavor_string}/${version}.${release}
else
    module load mpich/${compiler}-${provider}${pmix_string}${flavor_string}/${version}.${release}
fi


# This is used on the anfedclx8 machine
if [ "$flavor" == "gpu" ]; then
    export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH
else
    export LD_LIBRARY_PATH=/usr/lib64:/opt/dg1/clan-spir-1.1/lib:$LD_LIBRARY_PATH
fi

export LD_LIBRARY_PATH=${OFI_DIR}/lib:/opt/intel/csr/lib:/opt/intel/csr/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

export PATH=/opt/intel/csr/bin:$PATH

# PMIX related options
if [ "$pmix" == "pmix" ]; then
    export LD_LIBRARY_PATH=$pmix_dir/lib:$prte_dir/lib:$LD_LIBRARY_PATH
    export PATH=$pmix_dir/bin:$prte_dir/bin:$PATH
    if [ "$flavor" == "gpu" ]; then
        # GPU testing purpose, currently it is hard-coded to Qiao's home folder for testing PMix/GPU.
        export LD_LIBRARY_PATH=/home/qkang/opt/prte-3.0.0/lib:/home/qkang/opt/pmix-4.2.2/lib:$LD_LIBRARY_PATH
        export PATH=/home/qkang/opt/prte-3.0.0/bin:/home/qkang/opt/pmix-4.2.2/bin:$PATH
    fi
fi

if [ "$provider" == "sockets" -o "$provider" == "tcp" ]; then
    # set paths for daos
    export PATH=$DAOS_INSTALL_DIR/bin/:$PATH
    export LD_LIBRARY_PATH=$DAOS_INSTALL_DIR/lib/:$DAOS_INSTALL_DIR/lib64/:$LD_LIBRARY_PATH
    # daos has its own libfabric in lib, need to overwrite
    export LD_LIBRARY_PATH=$OFI_DIR/lib/:$LD_LIBRARY_PATH
fi

# print json files paths
echo $MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE
echo $MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE

export MPITEST_DATATYPE_TEST_LEVEL=min

# Validate version string
if [ "${job}" != "nightly" ]; then
    verstr=`${MPI_DIR}/bin/mpichversion | grep "MPICH Custom Information:" | awk '{print $4;}'`
    expected_verstr="drop${version}_release${release}"
    if [ "$verstr" != "$expected_verstr" ]; then
        echo "Custom version string mismatch: expected \"$expected_verstr\" but got \"$verstr\""
        exit 1
    fi
fi

echo "checking automake..."
PATH=$HOME/software/autotools/bin:/bin:$PATH
echo $PATH

AUTOTOOLS_DIR="/home/sys_csr1/software/autotools/bin"
export PATH=$AUTOTOOLS_DIR:$PATH

if [ ! -d /home/sys_csr1/software ] ; then
    exit 1;
fi

which ${AUTOTOOLS_DIR}/automake
./autogen.sh --with-autotools=${AUTOTOOLS_DIR} --without-ucx
#from test dir
cd test/mpi
./autogen.sh --with-autotools=${AUTOTOOLS_DIR}

if [ "$testgpu" == "0" ]; then
    find . -name testlist.gpu -exec rm '{}' \; -and -exec touch '{}' \;
    config_opts="$config_opts --without-ze"
fi

if [ "${flavor}" == "regular" ]; then
    export MPITEST_GPU_ENABLED=1
fi

error_checking=""
if [ "$configs" == "default" ]; then
    error_checking=--disable-checkerrors
elif [ "$configs" == "debug" ]; then
    error_checking=--enable-checkerrors
fi

ldd ${MPI_DIR}/lib/libmpich.so

echo "rpm-testing: slurm allocated node is: "`srun -N 1 -n 1 hostname`
echo "rpm-testing: test/mpi/configure will run on hostname: ${HOSTNAME}"

# setting for GPU
export NEOReadDebugKeys=1
export EnableWalkerPartition=0
export EnableImplicitScaling=0
# ULLS is buggy on ATS cluster, turning it off for now
export EnableDirectSubmission=0

./configure --with-mpi=${MPI_DIR} --disable-perftest --disable-ft-tests ${error_checking} ${config_opts} \
    CC=mpicc CXX=mpicxx F77=mpif77 FC=mpif90

# set xfails here
cd ../../
cp ${BUILD_SCRIPT_DIR}/set_xfail.py ${WORKSPACE}/set_xfail.py
xfail_file=${WORKSPACE}/maint/jenkins/xfail.conf

provider_string="${provider}"
if [ "$provider" == "verbs" ]; then
    provider_string="verbs;ofi_rxm"
elif [ "$provider" == "tcp" ]; then
    provider_string="tcp;ofi_rxm"
elif [ "${provider}" == "all" ]; then # If using a build with no default provider, the sockets provider
                                      # will be selected so use that for testing
    provider_string="sockets"
fi

python3 ${WORKSPACE}/set_xfail.py -j validation -c ${compiler} -o ${configs} -s ${direct} \
    -m "${provider_string}" -a ${force_am} -f ${xfail_file} -p ${pmix}

# For the GPU clusters, we need to additionally xfail all of the known problems with GPUs
if [ "$flavor" == "gpu" ]; then
    python3 ${WORKSPACE}/set_xfail.py -j per-commit-gpu -c ${compiler} -o ${configs} -s ${direct} \
        -m "${provider_string}" -a ${force_am} -f ${xfail_file} -p ${pmix}
fi

cd test/mpi
make clean
echo "rpm-testing: make testing will run on hostname: ${HOSTNAME}"
if [ "${pmix}" == "pmix" ]; then
    prte &
    export prte_pid=$!
    echo $prte_pid
    sleep 2
    make testing MPIEXEC="prun --pid=$prte_pid" MPITEST_PROGRAM_WRAPPER="--map-by :OVERSUBSCRIBE" MPITEST_PPNARG="-ppn 1 "
    if [ $? != 0 ]; then
        fail=1
    fi
    pterm --pid=$prte_pid
else
    make testing
    if [ $? != 0 ]; then
        fail=1
    fi
fi
cp summary.junit.xml ${WORKSPACE}

if [ "$flavor" == "gpu" ]; then
    rm -rf /tmp/inst
    rm -rf /tmp/rpmdb
else
    sudo rpm -e $RPM
fi

if [ "$nodes" -gt "1" ]; then
   if [ "$flavor" == "gpu" ]; then
       srun -N 1 -n 1 -e 1 $BUILD_SCRIPT_DIR/install_drop_rpm.sh 1 ${WORKSPACE}/$RPM.rpm
   else
       srun -N 1 -n 1 -r 1 sudo rpm -e $RPM
   fi
fi

exit $fail
