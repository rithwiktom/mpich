#!/bin/bash

set -x

WORKSPACE="$PWD"
SCRIPT_DIR=$(dirname $BASH_SOURCE[0])
JENKINS_DIR=$(dirname $SCRIPT_DIR)
device="ch4"
channel="" # CH3 channel -- becomes ":nememsis" if ch3
compiler="gnu"
neo_dir="" # For custom NEO builds for L0
ze_dir=""
ze_native="" # ZE GPU type to pass to yaksa for improved kernel loading
test_coverage="cpu-gpu"
jenkins_configure="default"
netmod="ofi"
direct="auto"
config_opts=
ofi_prov="all"
ofi_dir="/opt/intel/csr"
psm2_dir="/usr"
psm2_dir_list="/opt/intel/csr /home/sys_csr1/software/psm2" # list of locations where we might have libpsm2
verbs_dir="/usr"
verbs_dir_list="/opt/intel/csr /home/sys_csr1/software/verbs" # list of locations where we might have libibverbs
use_pmix="nopmix"
pmix_dir="/opt/openpmix"
prte_dir="/opt/prrte"
cxi_dir="/usr"
cxi_dir_list="/opt/intel/csr /home/sys_csr1/software/cxi" # list of locations where we might have libcxi
ofi_sockets_def_conn_map_sz=4096
N_MAKE_JOBS=8
BUILD_MODE="per-commit"
BUILD_A20="no"
results="$HOME"
test_multiplier=1.0
run_tests="yes"
build_tests="yes"
install_dir="$WORKSPACE/_inst"
src_dir="."
embed_ofi="no"
build_mpich="yes"
warnings_checker="no"
device_caps=""
cpu=""
thread_cs="" # Default will be set later depending on the device
mt_model="runtime"
force_am="noam"
xfail_file=""
config_opt=""
shm_eager=""
daos="no" # Per-commit build will not have DAOS by default, only drop build is using DAOS for now
DAOS_INSTALL_DIR="/usr"
DAOS_OPTS=""
set_xfail="#set-xfail.sh"
custom_version_string=drop
if [ -f "$JENKINS_DIR/drop_version" ]; then
    custom_version_string=drop$(<$JENKINS_DIR/drop_version)
fi
core_dir="/tmp/jenkins-core-files" # Directory to store core files
use_xpmem="yes"
use_gpudirect="yes"
use_json="yes"
xpmem_dir="/usr/local"
USE_GCC_9=0
USE_ICX="yes"
fast="none"

GENGBIN_NEO=/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021

MPICHLIB_CFLAGS=
MPICHLIB_CXXFLAGS=
MPICHLIB_FCFLAGS=
MPICHLIB_F77FLAGS=
MPICHLIB_LDFLAGS=
COMPILER_CFLAGS=
COMPILER_CFLAGS_OPTS=
COMPILER_CXXFLAGS=
COMPILER_CXXFLAGS_OPTS=
COMPILER_FFLAGS=
COMPILER_FFLAGS_OPTS=
COMPILER_FCFLAGS=
COMPILER_FCFLAGS_OPTS=
COMPILER_LDFLAGS=
COMPILER_LDFLAGS_OPTS=

# Capture command line parameters

cmdline="$0"
for a in "$@"; do
    cmdline="$cmdline '$a'"
done

#####################################################################
## Initialization
#####################################################################

while getopts ":a:A:b:B:c:d:D:e:E:f:F:g:G:h:H:i:I:j:J:k:l:m:M:n:N:o:p:P:q:r:s:t:u:v:w:W:x:X:y:Y:z:Z:" opt; do
    case "$opt" in
        a)
            cpu=$OPTARG ;;
        A)
            build_tests=$OPTARG ;;
        b)
            BUILD_MODE=$OPTARG ;;
        B)
            BUILD_A20=$OPTARG ;;
        c)
            compiler=$OPTARG ;;
        d)
            force_am=$OPTARG ;;
        D)
            daos=$OPTARG ;;
        e)
            EXTRA_MPICHLIB_CFLAGS=$OPTARG ;;
        E)
            use_xpmem=$OPTARG ;;
        f)
            install_dir=$OPTARG ;;
        F)
            fast=$OPTARG ;;
        g)
            device=$OPTARG ;;
        G)
            test_coverage=$OPTARG ;;
        h)
            WORKSPACE=$OPTARG ;;
        H)
            use_gpudirect=$OPTARG ;;
        i)
            ofi_dir=$OPTARG ;;
        I)
            USE_ICX=$OPTARG ;;
        j)
            config_opts=$OPTARG ;;
        J)
            use_json=$OPTARG ;;
        k)
            embed_ofi=$OPTARG ;;
        l)
            thread_cs=$OPTARG ;;
        m)
            N_MAKE_JOBS=$OPTARG ;;
        M)
            mt_model=$OPTARG ;;
        n)
            netmod=$OPTARG ;;
        N)
            neo_dir=$OPTARG ;;
        o)
            jenkins_configure=$OPTARG ;;
        p)
            ofi_prov=$OPTARG ;;
        P)
            use_pmix=$OPTARG ;;
        q)
            build_mpich=$OPTARG ;;
        r)
            results=$OPTARG ;;
        s)
            direct=$OPTARG ;;
        t)
            test_multiplier=$OPTARG ;;
        u)
            src_dir=$OPTARG ;;
        v)
            shm_eager=$OPTARG ;;
        w)
            xfail_file=$OPTARG ;;
        W)
            warnings_checker=$OPTARG ;;
        x)
            run_tests=$OPTARG ;;
        X)
            xpmem_dir=$OPTARG ;;
        y)
            custom_version_string=$OPTARG ;;
        Y)
            ze_native=$OPTARG ;;
        z)
            EXTRA_MPICHLIB_LDFLAGS=$OPTARG ;;
        Z)
            ze_dir=$OPTARG ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
    esac
done

# Convert the provider string to proper form
if [ "$ofi_prov" = "verbs" ]; then
    ofi_prov="verbs;ofi_rxm"
fi

cd $WORKSPACE

#####################################################################
## Functions
#####################################################################

CollectResults() {
    echo "RESULTS: $results";
    set -x

    find . \
        \( -name "filtered-make.txt" \
        -o -name "apply-xfail.sh" \
        -o -name "autogen.log" \
        -o -name "config.log" \
        -o -name "c.txt" \
        -o -name "m.txt" \
        -o -name "mi.txt" \
        -o -name "summary.junit.xml" \
        -o -name "script.qs.*" \) \
        | while read -r line; do
            mkdir -p "$results/$(dirname $line)"
        done

    find . \
        \( -name "filtered-make.txt" -o \
        -name "apply-xfail.sh" -o \
        -name "autogen.log" -o \
        -name "config.log" -o \
        -name "c.txt" -o \
        -name "m.txt" -o \
        -name "mi.txt" -o \
        -name "summary.junit.xml" -o \
        -name "script.qs.*" \) \
        -exec cp {} $results/{} \;

    # Record the command line string, including some environment variables

    if [ "$CFLAGS" != "" ]; then
	cmdline="CFLAGS='$CFLAGS' $cmdline"
    fi
    if [ "$CXXFLAGS" != "" ]; then
	cmdline="CXXFLAGS='$CXXFLAGS' $cmdline"
    fi
    if [ "$FCFLAGS" != "" ]; then
	cmdline="FCFLAGS='$FCFLAGS' $cmdline"
    fi
    if [ "$F77FLAGS" != "" ]; then
	cmdline="F77FLAGS='$F77FLAGS' $cmdline"
    fi
    # LDFLAGS is overwritten by us anyway - so do not capture it

    if [ "$EXTRA_MPICHLIB_CFLAGS" != "" ]; then
	cmdline="EXTRA_MPICHLIB_CFLAGS='$EXTRA_MPICHLIB_CFLAGS' $cmdline"
    fi
    if [ "$EXTRA_MPICHLIB_CXXFLAGS" != "" ]; then
	cmdline="EXTRA_MPICHLIB_CXXFLAGS='$EXTRA_MPICHLIB_CXXFLAGS' $cmdline"
    fi
    if [ "$EXTRA_MPICHLIB_FCFLAGS" != "" ]; then
	cmdline="EXTRA_MPICHLIB_FCFLAGS='$EXTRA_MPICHLIB_FCFLAGS' $cmdline"
    fi
    if [ "$EXTRA_MPICHLIB_F77FLAGS" != "" ]; then
	cmdline="EXTRA_MPICHLIB_F77FLAGS='$EXTRA_MPICHLIB_F77FLAGS' $cmdline"
    fi
    if [ "$EXTRA_MPICHLIB_LDFLAGS" != "" ]; then
	cmdline="EXTRA_MPICHLIB_LDFLAGS='$EXTRA_MPICHLIB_LDFLAGS' $cmdline"
    fi

    echo $cmdline > $results/test-worker-cmdline.txt

    if [ "$run_tests" = "yes" ]; then
	cores=`find ./test/mpi -name 'core.*'`
	if [ -n "${cores}" ]; then
	    mkdir -p ${core_dir}
	    chgrp csr ${core_dir}
	    chmod 775 ${core_dir} # Allow "csr" group users to remove the files
	    echo "CORES: ${core_dir}"
	    echo "Core files found:"
	    echo "${cores}"
	    for c in ${cores}; do
		cp $c ${core_dir}
	    done
	else
	    echo "Core files not found."
	fi
    fi
}

PrepareEnv() {
    # Search for psm2
    for d in $psm2_dir_list; do
	if [ -f "$d/lib64/libpsm2.so" ]; then
	    psm2_dir=$d
	    break
	fi
    done

    for d in $verbs_dir_list; do
        if [ -f "$d/lib64/libibverbs.so" ]; then
            verbs_dir=$d
            break
        fi
    done

    for d in $cxi_dir_list; do
        if [ -f "$d/lib64/libcxi.so" ]; then
            cxi_dir=$d
            break
        fi
    done

    PATH=$HOME/software/autotools/bin:/bin:$PATH

    if [ "$use_xpmem" = "yes" ]; then
        # The XPMEM libraries live here
        LD_LIBRARY_PATH=${xpmem_dir}/lib:$LD_LIBRARY_PATH
    fi

    if [ "$embed_ofi" != "yes" ]; then
        LD_LIBRARY_PATH=$ofi_dir/lib:$psm2_dir/lib64:${verbs_dir}/lib64:$LD_LIBRARY_PATH
    fi

    if [ "$neo_dir" != "" ]; then
        # add neo dir before /usr/lib64 where older neo is installed on A20 compute nodes
        export LDFLAGS="${LD_FLAGS} -L$neo_dir/lib64"
    fi

    export PATH
    echo "$PATH"
    export LD_LIBRARY_PATH
    echo "$LD_LIBRARY_PATH"

    # Prepare for huge number of connections
    # This may be necessary to enable some test cases with per-window EP
    # model where a huge number of outstanding connections could be created.
    # See fi_sockets(7) for details.
    export FI_SOCKETS_DEF_CONN_MAP_SZ=$ofi_sockets_def_conn_map_sz

    # Use the odd even cliques code
    if [ "$direct" != "no-odd-even" ]; then
        export MPIR_CVAR_ODD_EVEN_CLIQUES=1
    fi

    # Prevents core dump generation
    ulimit -c unlimited
}

SetCompiler() {
    #Remove all the default modules that are loaded for a clean env
    module purge

    case "$compiler" in
        "gnu")
            if [ -f /opt/rh/devtoolset-7/enable ]; then
                source /opt/rh/devtoolset-7/enable
            elif [ -f /opt/rh/devtoolset-6/enable ]; then
                source /opt/rh/devtoolset-6/enable
            elif [ -f /opt/rh/devtoolset-4/enable ]; then
                source /opt/rh/devtoolset-4/enable
            elif [ -f /opt/rh/devtoolset-3/enable ]; then
                source /opt/rh/devtoolset-3/enable
            elif [[ "$(module whatis gnu9)" == "gnu9"* ]]; then
                # This check is kind of hacky. module is-avail does not seem to work
                module load gnu9
                USE_GCC_9=1
            fi
            CC=gcc
            CXX=g++
            F77=gfortran
            FC=gfortran
            LD="ld"
            AR="gcc-ar"

            IVY_BRIDGE_OPT="-msse2 -msse4.2 -mcrc32 -mavx"
            HASWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            BROADWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            KNL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f"
            SKL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f -march=skylake-avx512"

	    GNU_DETERMINISTIC_FLAGS="-fno-associative-math -fno-rounding-math -fno-tree-vectorization"

#            if [ "${jenkins_configure}" = "debug" ]; then
#                config_opt+="--enable-coverage"
#            fi
            export NM="gcc-nm"
            export RANLIB="gcc-ranlib"
            if [ "$embed_ofi" != "yes" ]; then
                export LDFLAGS="${LDFLAGS} -L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 -Wl,-z,now"
            else
                export LDFLAGS="${LDFLAGS} -Wl,-z,now"
            fi
            #. ${PWD}/setup_gnu.sh
            COMPILER_CFLAGS="-ggdb -Wall -mtune=generic -std=gnu99"
            COMPILER_CFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -std=gnu99 -Wall"
            COMPILER_CXXFLAGS="-ggdb -Wall -mtune=generic"
            COMPILER_CXXFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -Wall"
            COMPILER_FFLAGS="-ggdb -mtune=generic"
            COMPILER_FFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_FCFLAGS="-ggdb -mtune=generic"
            COMPILER_FCFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_F77FLAGS="-ggdb -mtune=generic"
            COMPILER_F77FLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_LDFLAGS="-mtune=generic"
            COMPILER_LDFLAGS_OPTS="-mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -fuse-linker-plugin"

	    # set flags for deterministic result
	    if [ "$jenkins_configure" = "debug" ]; then
		COMPILER_CFLAGS_OPTS="$GNU_DETERMINISTIC_FLAGS $COMPILER_CFLAGS_OPTS"
                COMPILER_CXXFLAGS_OPTS="$GNU_DETERMINISTIC_FLAGS $COMPILER_CXXFLAGS_OPTS"
                COMPILER_FFLAGS_OPTS="$GNU_DETERMINISTIC_FLAGS $COMPILER_FFLAGS_OPTS"
                COMPILER_F77FLAGS_OPTS="$GNU_DETERMINISTIC_FLAGS $COMPILER_F77FLAGS_OPTS"
	    fi

            case "$cpu" in
                "ivy_bridge")
                    COMPILER_CFLAGS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "haswell")
                    COMPILER_CFLAGS="$HASWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$HASWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$HASWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$HASWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$HASWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$HASWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$HASWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$HASWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$HASWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$HASWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$HASWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$HASWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "broadwell")
                    COMPILER_CFLAGS="$BROADWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$BROADWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$BROADWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$BROADWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$BROADWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$BROADWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$BROADWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$BROADWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "knl")
                    COMPILER_CFLAGS="$KNL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$KNL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$KNL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$KNL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$KNL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$KNL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$KNL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$KNL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$KNL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$KNL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$KNL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$KNL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "skylake")
                    COMPILER_CFLAGS="$SKL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$SKL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$SKL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$SKL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$SKL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$SKL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$SKL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$SKL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$SKL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$SKL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$SKL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$SKL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
            esac
            ;;

        "gnu-4.8")
            if [ -f /opt/rh/devtoolset-3/enable ]; then
                source /opt/rh/devtoolset-3/enable
            else
                echo "GCC 4.8 installation was not found!"
                exit 1
            fi
            CC=gcc
            CXX=g++
            F77=gfortran
            FC=gfortran
            LD="ld"
            AR="gcc-ar"

            IVY_BRIDGE_OPT="-msse2 -msse4.2 -mcrc32 -mavx"
            HASWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            BROADWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            KNL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f"
            SKL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f -march=skylake-avx512"

#            if [ "${jenkins_configure}" = "debug" ]; then
#                config_opt+="--enable-coverage"
#            fi
            export NM="gcc-nm"
            export RANLIB="gcc-ranlib"
            if [ "$embed_ofi" != "yes" ]; then
                export LDFLAGS="${LDFLAGS} -L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 -Wl,-z,now"
            else
                export LDFLAGS="${LDFLAGS} -Wl,-z,now"
            fi
            #. ${PWD}/setup_gnu.sh
            COMPILER_CFLAGS="-ggdb -Wall -mtune=generic -std=gnu99"
            COMPILER_CFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -std=gnu99 -Wall"
            COMPILER_CXXFLAGS="-ggdb -Wall -mtune=generic"
            COMPILER_CXXFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -Wall"
            COMPILER_FFLAGS="-ggdb -mtune=generic"
            COMPILER_FFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_FCFLAGS="-ggdb -mtune=generic"
            COMPILER_FCFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_F77FLAGS="-ggdb -mtune=generic"
            COMPILER_F77FLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_LDFLAGS="-mtune=generic"
            COMPILER_LDFLAGS_OPTS="-mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -fuse-linker-plugin"

            case "$cpu" in
                "ivy_bridge")
                    COMPILER_CFLAGS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "haswell")
                    COMPILER_CFLAGS="$HASWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$HASWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$HASWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$HASWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$HASWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$HASWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$HASWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$HASWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$HASWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$HASWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$HASWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$HASWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "broadwell")
                    COMPILER_CFLAGS="$BROADWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$BROADWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$BROADWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$BROADWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$BROADWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$BROADWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$BROADWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$BROADWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "knl")
                    COMPILER_CFLAGS="$KNL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$KNL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$KNL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$KNL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$KNL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$KNL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$KNL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$KNL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$KNL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$KNL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$KNL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$KNL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "skylake")
                    COMPILER_CFLAGS="$SKL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$SKL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$SKL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$SKL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$SKL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$SKL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$SKL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$SKL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$SKL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$SKL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$SKL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$SKL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
            esac
            ;;

        "gnu-8")
            if [ -f /opt/intel/csr/gcc-8.1.0/enable ]; then
                source /opt/intel/csr/gcc-8.1.0/enable
            elif [ -f /home/sys_csr1/software/gcc-8.1.0/enable ]; then
                . /home/sys_csr1/software/gcc-8.1.0/enable
            else
                echo "GCC 8 installation was not found!"
                exit 1
            fi

            CC=gcc
            CXX=g++
            F77=gfortran
            FC=gfortran
            LD="ld"
            AR="gcc-ar"

#            if [ "${jenkins_configure}" = "debug" ]; then
#                config_opt+="--enable-coverage"
#            fi
            IVY_BRIDGE_OPT="-msse2 -msse4.2 -mcrc32 -mavx"
            HASWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            BROADWELL_OPT="-msse2 -msse4.2 -mcrc32 -mavx2"
            KNL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f"
            SKL_OPT="-msse2 -msse4.2 -mcrc32 -mavx512f -march=skylake-avx512"

            export NM="gcc-nm"
            export RANLIB="gcc-ranlib"
            if [ "$embed_ofi" != "yes" ]; then
                export LDFLAGS="${LDFLAGS} -L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 -Wl,-z,now"
            else
                export LDFLAGS="${LDFLAGS} -Wl,-z,now"
            fi
            #. ${PWD}/setup_gnu.sh
            COMPILER_CFLAGS="-ggdb -Wall -mtune=generic -std=gnu99"
            COMPILER_CFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -std=gnu99 -Wall"
            COMPILER_CXXFLAGS="-ggdb -Wall -mtune=generic"
            COMPILER_CXXFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -Wall"
            COMPILER_FFLAGS="-ggdb -mtune=generic"
            COMPILER_FFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_FCFLAGS="-ggdb -mtune=generic"
            COMPILER_FCFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_F77FLAGS="-ggdb -mtune=generic"
            COMPILER_F77FLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions -finline-limit=2147483647 -mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0"
            COMPILER_LDFLAGS="-mtune=generic"
            COMPILER_LDFLAGS_OPTS="-mtune=generic -flto=32 -flto-partition=balanced --param inline-unit-growth=300 --param ipcp-unit-growth=300 --param large-function-insns=500000000 --param large-function-growth=5000000000 --param large-stack-frame-growth=5000000 --param max-inline-insns-single=2147483647 --param max-inline-insns-auto=2147483647 --param inline-min-speedup=0 -fuse-linker-plugin"

            case "$cpu" in
                "ivy_bridge")
                    COMPILER_CFLAGS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "haswell")
                    COMPILER_CFLAGS="$HASWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$HASWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$HASWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$HASWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$HASWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$HASWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$HASWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$HASWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$HASWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$HASWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$HASWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$HASWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "broadwell")
                    COMPILER_CFLAGS="$BROADWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$BROADWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$BROADWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$BROADWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$BROADWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$BROADWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$BROADWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$BROADWELL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "knl")
                    COMPILER_CFLAGS="$KNL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$KNL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$KNL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$KNL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$KNL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$KNL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$KNL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$KNL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$KNL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$KNL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$KNL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$KNL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
                "skylake")
                    COMPILER_CFLAGS="$SKL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$SKL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$SKL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$SKL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$SKL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$SKL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$SKL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$SKL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$SKL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$SKL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$SKL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS="$SKL_OPT $COMPILER_LDFLAGS_OPTS"
                    ;;
            esac
            ;;
        "clang")
            CC=clang
            CXX=clang++
            F77=gfortran
            FC=gfortran
            ;;
        "icc")

	    INTEL_DETERMINISTIC_FLAGS="-fp-model precise -fp-model source -fimf-arch-consistency=true"

            if [ -f /opt/rh/devtoolset-7/enable ]; then
                source /opt/rh/devtoolset-7/enable
            elif [ -f /opt/rh/devtoolset-6/enable ]; then
                source /opt/rh/devtoolset-6/enable
            elif [ -f /opt/rh/devtoolset-4/enable ]; then
                source /opt/rh/devtoolset-4/enable
            elif [ -f /opt/rh/devtoolset-3/enable ]; then
                source /opt/rh/devtoolset-3/enable
            fi

            if [ -f /opt/intel/inteloneapi/compiler/latest/env/vars.sh ]; then
                . /opt/intel/inteloneapi/compiler/latest/env/vars.sh intel64
                # Starting ICC2019 update 2, FI_PROVIDER_PATH is set to
                # /opt/intel/compilers_and_libraries_2019.4.243/linux/mpi/intel64/libfabric/lib/prov
                # We unset it because we dont want the provider to come from this location.
                unset FI_PROVIDER_PATH
            elif [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ]; then
                # This is the location for ICC on A20
                . /opt/intel/oneapi/compiler/latest/env/vars.sh intel64
                # Starting ICC2019 update 2, FI_PROVIDER_PATH is set to
                # /opt/intel/compilers_and_libraries_2019.4.243/linux/mpi/intel64/libfabric/lib/prov
                # We unset it because we dont want the provider to come from this location.
                unset FI_PROVIDER_PATH
            fi
            CC=icc
            CXX=icpc
            F77=ifort
            FC=ifort
            LD="xild"
            AR=xiar

            if [ "$USE_ICX" = "yes" ]; then
                CC=icx
                CXX=icpx
                F77=ifort
                FC=ifort
                # https://software.intel.com/content/www/us/en/develop/articles/porting-guide-for-icc-users-to-dpcpp-or-icx.html
                # xild and xiar have been removed from icx/icpx. The above link suggests replacing usage with the native linker/archiver
                LD=ld
                AR=ar
            fi

            IVY_BRIDGE_OPT="-xAVX"
            HASWELL_OPT="-xCORE-AVX2"
            BROADWELL_OPT="-xCORE-AVX2"
            KNL_OPT="-xCORE-AVX512"
            SKL_OPT="-xCORE-AVX512"

            if [ "$embed_ofi" != "yes" ]; then
                export LDFLAGS="${LDFLAGS} -L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 -Wl,-z,now"
            else
                export LDFLAGS="${LDFLAGS} -Wl,-z,now"
            fi
            if [ "$USE_ICX" = "yes" ]; then
                COMPILER_CFLAGS="-ggdb -mtune=generic -std=gnu11 -Wall"
                COMPILER_CFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -std=gnu11 -Wall"
                COMPILER_CXXFLAGS="-ggdb -mtune=generic -Wall"
                COMPILER_CXXFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -Wall"
                COMPILER_FFLAGS="-ggdb -mtune=generic -w"
                COMPILER_FFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_FCFLAGS="-ggdb -mtune=generic -w"
                COMPILER_FCFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_F77FLAGS="-ggdb -mtune=generic -w"
                COMPILER_F77FLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_LDFLAGS="-ggdb -mtune=generic -w"
                COMPILER_LDFLAGS_OPTS="-ipo -qopt-report-phase=ipo -qopt-report=5 -mtune=generic"
            else
                COMPILER_CFLAGS="-ggdb -mtune=generic -std=gnu99 -Wcheck -Wall -w3 -wd869 -wd280 -wd593 -wd2259 -wd981 -static-intel"
                COMPILER_CFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -std=gnu99 -Wcheck -Wall -w3 -wd869 -wd280 -wd593 -wd2259 -wd981"
                COMPILER_CXXFLAGS="-ggdb -mtune=generic -Wcheck -Wall -w3 -wd869 -wd280 -wd593 -wd2259 -wd981 -static-intel"
                COMPILER_CXXFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -Wcheck -Wall -w3 -wd869 -wd280 -wd593 -wd2259 -wd981"
                COMPILER_FFLAGS="-ggdb -mtune=generic -w -static-intel"
                COMPILER_FFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_FCFLAGS="-ggdb -mtune=generic -w -static-intel"
                COMPILER_FCFLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_F77FLAGS="-ggdb -mtune=generic -w -static-intel"
                COMPILER_F77FLAGS_OPTS="-ggdb -DNVALGRIND -DNDEBUG -falign-functions=16 -ipo -inline-factor=10000 -inline-min-size=0 -ansi-alias -mtune=generic -w"
                COMPILER_LDFLAGS="-ggdb -mtune=generic -w -static-intel"
                COMPILER_LDFLAGS_OPTS="-ipo -qopt-report-phase=ipo -qopt-report=5 -mtune=generic"
            fi

	    # set flags for deterministic result
	    if [ "$jenkins_configure" = "debug" ]; then
		COMPILER_CFLAGS_OPTS="$INTEL_DETERMINISTIC_FLAGS $COMPILER_CFLAGS_OPTS"
                COMPILER_CXXFLAGS_OPTS="$INTEL_DETERMINISTIC_FLAGS $COMPILER_CXXFLAGS_OPTS"
                COMPILER_FFLAGS_OPTS="$INTEL_DETERMINISTIC_FLAGS $COMPILER_FFLAGS_OPTS"
                COMPILER_F77FLAGS_OPTS="$INTEL_DETERMINISTIC_FLAGS $COMPILER_F77FLAGS_OPTS"
	    fi

            case "$cpu" in
                "ivy_bridge")
                    COMPILER_CFLAGS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$IVY_BRIDGE_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$IVY_BRIDGE_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS=$IVY_BRIDGE_OPT $COMPILER_LDFLAGS_OPTS
                    ;;
                "haswell")
                    COMPILER_CFLAGS="$HASWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$HASWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$HASWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$HASWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$HASWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$HASWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$HASWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$HASWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$HASWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$HASWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$HASWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS=$HASWELL_OPT $COMPILER_LDFLAGS_OPTS
                    ;;
                "broadwell")
                    COMPILER_CFLAGS="$BROADWELL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$BROADWELL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$BROADWELL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$BROADWELL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$BROADWELL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$BROADWELL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$BROADWELL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$BROADWELL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$BROADWELL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS=$BROADWELL_OPT $COMPILER_LDFLAGS_OPTS
                    ;;
                "knl")
                    COMPILER_CFLAGS="$KNL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$KNL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$KNL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$KNL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$KNL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$KNL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$KNL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$KNL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$KNL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$KNL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$KNL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS=$KNL_OPT $COMPILER_LDFLAGS_OPTS
                    ;;
                "skylake")
                    COMPILER_CFLAGS="$SKL_OPT $COMPILER_CFLAGS"
                    COMPILER_CFLAGS_OPTS="$SKL_OPT $COMPILER_CFLAGS_OPTS"
                    COMPILER_CXXFLAGS="$SKL_OPT $COMPILER_CXXFLAGS"
                    COMPILER_CXXFLAGS_OPTS="$SKL_OPT $COMPILER_CXXFLAGS_OPTS"
                    COMPILER_FFLAGS="$SKL_OPT $COMPILER_FFLAGS"
                    COMPILER_FFLAGS_OPTS="$SKL_OPT $COMPILER_FFLAGS_OPTS"
                    COMPILER_FCFLAGS="$SKL_OPT $COMPILER_FCFLAGS"
                    COMPILER_FCFLAGS_OPTS="$SKL_OPT $COMPILER_FCFLAGS_OPTS"
                    COMPILER_F77FLAGS="$SKL_OPT $COMPILER_F77FLAGS"
                    COMPILER_F77FLAGS_OPTS="$SKL_OPT $COMPILER_F77FLAGS_OPTS"
                    COMPILER_LDFLAGS="$SKL_OPT $COMPILER_LDFLAGS"
                    COMPILER_LDFLAGS_OPTS=$SKL_OPT $COMPILER_LDFLAGS_OPTS
                    ;;
            esac
            ;;
        *)
            echo "Unknown compiler suite"
            exit 1
    esac

    export CC
    export CXX
    export F77
    export FC
    export LD
    export AR

    which $CC
    which $CXX
    which $F77
    which $FC
    echo $PATH
    echo $LD_LIBRARY_PATH

    module list
}

SetNetmod() {
    echo "$netmod_opt"
}

SetConfigOpt() {
    netmod_opt=""

    if [ "$device" != "ch3" -a "$device" != "ch4" ]; then
        echo "BAD DEVICE: ${device}\n";
        exit 1;
    fi

    config_opt+=( --with-custom-version-string=${custom_version_string} )
    config_opts_without_space=`echo $config_opts | sed 's/\ //g'`
    if [[ "$config_opts_without_space" != *"--enable-ofi-domain"* ]]; then
        config_opt+=( --disable-ofi-domain )
    fi

    config_opt+=( --disable-ft-tests )
    config_opt+=( -with-fwrapname=mpigf )
    if [ "$ofi_prov" = "sockets" -a "$daos" = "yes" ]; then
        config_opt+=( -with-file-system=ufs+nfs+daos )
        if [ -f /opt/daos-34 ]; then
            DAOS_INSTALL_DIR="/opt/daos-34"
        fi
        DAOS_OPTS=" --with-daos=$DAOS_INSTALL_DIR --with-cart=$DAOS_INSTALL_DIR"
        config_opt+=( $DAOS_OPTS )
    else
        config_opt+=( -with-file-system=ufs+nfs )
    fi
    config_opt+=( -enable-timer-type=linux86_cycle )
    config_opt+=( -with-assert-level=0 )
    config_opt+=( -enable-shared )
    config_opt+=( -enable-static )
    config_opt+=( -enable-error-messages=yes )
    config_opt+=( -enable-large-tests )
    if [ "$warnings_checker" = "yes" ]; then
        config_opt+=( -enable-strict=error )
    else
        config_opt+=( -enable-strict )
    fi
    config_opt+=( -enable-collalgo-tests )
    config_opt+=( -enable-izem-queue )
    config_opt+=( -with-zm-prefix=yes )
    if [ "$direct" != "netmod" -a "$use_xpmem" = "yes" ]; then
        config_opt+=( -with-xpmem=${xpmem_dir} )
    fi

    # Prepare device specifier fragments (going to `--with-device=...`)
    if [ "$device" = "ch4" ]; then
        if [ "$jenkins_configure" = "debug" ]; then
            device_caps=""
        elif [ "x$ofi_prov" != "x" ]; then
            device_caps=":$ofi_prov"
        fi
        if [ "x$ofi_prov" != "x" -a "x$ofi_prov" != "all" ]; then
            config_opt+=( --with-default-ofi-provider=${ofi_prov})
        fi
        if [ "x${shm_eager}" != "x" -a "${direct}" != "none" ]; then
            config_opt+=(--with-ch4-posix-eager-modules=${shm_eager})
        fi
        channel=""
    elif [ "$device" = "ch3" ]; then
        channel=":nemesis"
        device_caps=""
    fi

    case "$fast" in
        "none")
            config_opt+=( -enable-fast=none )
            ;;
        "O3")
            config_opt+=( -enable-fast=all,O3 )
            ;;
        *)
            echo "Bad fast option: $fast"
            exit 1
    esac

    case "$jenkins_configure" in
        "debug")
            config_opt+=( -enable-g=all )
            config_opt+=( -enable-timing=runtime )
            config_opt+=( -enable-error-checking=all )
            config_opt+=( -enable-debuginfo )
            config_opt+=( -with-device=${device}${channel}:${netmod} )
            config_opt+=( -enable-handle-allocation=default )
            config_opt+=( -enable-threads=multiple )
            config_opt+=( -enable-ch4-netmod-inline=no )
            config_opt+=( -enable-ch4-shm-inline=no )
            config_opt+=( -enable-mpit-pvars=all )
            MPICHLIB_CFLAGS="-ggdb $EXTRA_MPICHLIB_CFLAGS $COMPILER_CFLAGS"
            MPICHLIB_CXXFLAGS="-ggdb $EXTRA_MPICHLIB_CXXFLAGS $COMPILER_CXXFLAGS"
            MPICHLIB_FCFLAGS="-ggdb $EXTRA_MPICHLIB_FCFLAGS $COMPILER_FCFLAGS"
            MPICHLIB_F77FLAGS="-ggdb $EXTRA_MPICHLIB_F77FLAGS $COMPILER_F77FLAGS"
            if [ "$embed_ofi" != "yes" ]; then
                MPICHLIB_LDFLAGS="-O0 -L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 $EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            else
                MPICHLIB_LDFLAGS="-O0 $EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            fi
            ;;
        "default")
            config_opt+=( -enable-g=none )
            config_opt+=( -enable-timing=none )
            config_opt+=( -enable-error-checking=no )
            config_opt+=( -disable-debuginfo )
            config_opt+=( -with-device=${device}${channel}:${netmod}${device_caps} )
            config_opt+=( -enable-handle-allocation=default )
            config_opt+=( -enable-threads=multiple )
            config_opt+=( -without-valgrind )
            config_opt+=( -enable-timing=none )
            MPICHLIB_CFLAGS="-ggdb $EXTRA_MPICHLIB_CFLAGS $COMPILER_CFLAGS"
            MPICHLIB_CXXFLAGS="-ggdb $EXTRA_MPICHLIB_CXXFLAGS $COMPILER_CXXFLAGS"
            MPICHLIB_FCFLAGS="-ggdb $EXTRA_MPICHLIB_FCFLAGS $COMPILER_FCFLAGS"
            MPICHLIB_F77FLAGS="-ggdb $EXTRA_MPICHLIB_F77FLAGS $COMPILER_F77FLAGS"
            if [ "$embed_ofi" != "yes" ]; then
                MPICHLIB_LDFLAGS="-L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 $EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            else
                MPICHLIB_LDFLAGS="$EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            fi
            ;;
        "opt")
            config_opt+=( -enable-g=none )
            config_opt+=( -enable-timing=none )
            config_opt+=( -enable-error-checking=no )
            config_opt+=( -disable-debuginfo )
            config_opt+=( -with-device=${device}${channel}:${netmod}${device_caps} )
            config_opt+=( -enable-handle-allocation=default )
            config_opt+=( -enable-threads=multiple )
            config_opt+=( -without-valgrind )
            config_opt+=( -enable-timing=none )
            if [ "$ofi_prov" != "psm" -a "$ofi_prov" != "psm2" -a "$ofi_prov" != "opa" -a "$ofi_prov" != "verbs;ofi_rxm"]; then
                config_opt+=( --enable-direct=$ofi_prov)
                netmod_opt+=(:direct-provider)
            fi
            MPICHLIB_CFLAGS="-ggdb $EXTRA_MPICHLIB_CFLAGS $COMPILER_CFLAGS_OPTS"
            MPICHLIB_CXXFLAGS="-ggdb $EXTRA_MPICHLIB_CXXFLAGS $COMPILER_CXXFLAGS_OPTS"
            MPICHLIB_FCFLAGS="-ggdb $EXTRA_MPICHLIB_FCFLAGS $COMPILER_FCFLAGS_OPTS"
            MPICHLIB_F77FLAGS="-ggdb $EXTRA_MPICHLIB_F77FLAGS $COMPILER_F77FLAGS_OPTS"
            if [ "$embed_ofi" != "yes" ]; then
                MPICHLIB_LDFLAGS="-L${ofi_dir}/lib -L${psm2_dir}/lib64 -L${verbs_dir}/lib64 -L${cxi_dir}/lib64 $EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            else
                MPICHLIB_LDFLAGS="$EXTRA_MPICHLIB_LDFLAGS $COMPILER_LDFLAGS"
            fi

            ;;
        *)
            echo "Bad configure option: $jenkins_configure"
            exit 1
    esac

    if [ "$USE_GCC_9" = "1" ]; then
        MPICHLIB_FCFLAGS="$MPICHLIB_F77FLAGS -ffree-line-length-256"
        MPICHLIB_F77FLAGS="$MPICHLIB_F77FLAGS -ffree-line-length-256"
    fi

    if [ "$device" = "ch4" ]; then
        # This assumes that the ofi source is already dropped in the correct
        # location and has been autogen'ed
        if [ "$embed_ofi" = "yes" ]; then
            prov_config=
            prov_config+=( --disable-efa)
            prov_config+=( --disable-usnic)

            # Add OFI config options
            if [ "$ofi_prov" = "psm2" -o "$ofi_prov" = "verbs;ofi_rxm" -o "$ofi_prov" = "cxi" -o "$ofi_prov" = "all" -o "$jenkins_configure" = "debug" ]; then
                # "$jenkins_configure" = "debug" => runtime capability sets => OFI subconfigure will
                # build in all possible providers, so we must specify psm2 location here regardless
                # of the provider the user specified. Otherwise this libfabric build will detect
                # system-installed psm2 (pretty old) which leads to a build failure.
                if [ "$ofi_prov" = "psm2" -o "$ofi_prov" = "all" ]; then
                    if [ -f "$psm2_dir/lib64/libpsm2.so" ]; then
                        enable_psm2=$psm2_dir
                    else
                        enable_psm2="yes"
                    fi
                    if [ "$BUILD_A20" = "yes" ]; then
                        prov_config+=( --disable-psm2)
                    else
                        prov_config+=( --enable-psm2=${enable_psm2})
                    fi
                else
                    prov_config+=( --disable-psm2)
                fi

                if [ "$ofi_prov" = "verbs;ofi_rxm" -o "$ofi_prov" = "all" ]; then
                    if [ -f "${verbs_dir}/lib64/libibverbs.so" ]; then
                        enable_verbs=${verbs_dir}
                    else
                        enable_verbs="yes"
                    fi
                    prov_config+=( --enable-verbs=${enable_verbs})
                else
                    prov_config+=( --disable-verbs)
                fi

                if [ "$ofi_prov" = "cxi" -o "$ofi_prov" = "all" ]; then
                    if [ -f "${cxi_dir}/lib64/libcxi.so" ]; then
                        enable_cxi=${cxi_dir}
                    else
                        enable_cxi="yes"
                    fi
                    prov_config+=( --enable-cxi=${enable_cxi})
                else
                    prov_config+=( --disable-cxi)
                fi
            fi

            if [ "$ofi_prov" = "opa2" -o "$ofi_prov" = "all" ]; then
                prov_config+=( --with-opa-headers=/usr)
            fi

            prov_config+=( --enable-embedded)

            ofi_dir="embedded"
            config_opt+=( ${prov_config[@]})
        fi

        if [ "$direct" = "auto" -o "$direct" = "no-odd-even" ]; then
            shmmods="posix"
            if [ "$ze_dir" != "" ]; then
                shmmods="${shmmods}"
            fi
            if [ "$use_xpmem" = "yes" ]; then
                shmmods="${shmmods},xpmem"
            fi
            if [ "$use_gpudirect" = "yes" ]; then
                shmmods="${shmmods},gpudirect"
            fi
            config_opt+=( --with-ch4-shmmods=${shmmods} )
        elif [ "$direct" = "netmod" ]; then
            config_opt+=( --with-ch4-shmmods=none )
        else
            # ch3 does not require `direct`
            echo "*** Wrong ch4-direct configuration specified. Specify auto or netmod for option '-s'. Aborting now ***"
            exit 1
        fi

        if [ "$force_am" = "am" ]; then
            config_opt+=( --enable-ch4-am-only )
        fi

	if [ "${thread_cs}" = "" ]; then
	    # For CH4, default is per-vci CS
	    thread_cs="per-vci"
	    # Set max vcis to a high number to run with oneCCL
	    config_opt+=" --with-ch4-max-vcis=64"
	elif [ "${thread_cs}" = "global" ]; then
	    # If global CS is specified, fall back to direct MT model,
	    # which is the only supported model with global CS
	    mt_model="direct"
	fi
        config_opt+=("--enable-ch4-mt=${mt_model}")

        if [ "${netmod_opt[@]}" != "" ]; then
            config_opt+=("--with-ch4-netmod-ofi-args=`printf "%s" "${netmod_opt[@]}"`")
        fi
    else
	# CH3
	if [ "${thread_cs}" = "" ]; then
	    # For CH3, default is global CS
	    thread_cs="global"
	fi
    fi

    config_opt+=( --enable-thread-cs=${thread_cs})
    # --with-libfabric: CH4, --with-ofi: CH3
    config_opt+=( --with-libfabric=$ofi_dir )

    # pmix option
    if [ "$use_pmix" = "pmix" ]; then
        config_opt+=( --with-pmi=pmix --with-pmix=$pmix_dir )
    fi

    export MPICHLIB_CFLAGS
    export MPICHLIB_CXXFLAGS
    export MPICHLIB_FCFLAGS
    export MPICHLIB_F77FLAGS
    export MPICHLIB_LDFLAGS

    config_opt+=($(echo ${config_opts}))

    echo "${config_opt[@]}"
}

#####################################################################
## Main() { Setup Environment and Build
#####################################################################
# determine if this is a nightly job or a per-commit job
PrepareEnv

SetCompiler "$compiler"
if [ "$build_mpich" == "yes" ]; then
    SetConfigOpt $jenkins_configure

    if [ "$ze_dir" != "" ]; then
        config_opt+=( --with-ze=${ze_dir} )
        if [ "$test_coverage" = "gpu" ]; then
            config_opt+=( --enable-gpu-tests-only )
        fi

        # NOTE: This assumes we are working on A20. Need to load the following modules here since
        # we run module purge in SetCompiler
        if [ -d /home/puser42/dg1_modules ]; then
            module use /home/puser42/dg1_modules
            module load neo/2020.10.05
        fi

        export LD_LIBRARY_PATH=${ze_dir}/lib64:$LD_LIBRARY_PATH

        # Check if this is an ATS build not running on jfcst-xe
        if [ "$neo_dir" == "$GENGBIN_NEO" && ! -d "$GENGBIN_NEO" ]; then
            neo_dir=/usr
        fi

        if [ "$neo_dir" == "$GENGBIN_NEO" ]; then
            export LD_LIBRARY_PATH=/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021/neo/build/bin:/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021/neo/build/lib:/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021/igc/lib:/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021/gmmlib/lib:$LD_LIBRARY_PATH
            export PATH=/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021/neo/build/bin:$PATH
        elif [ "$neo_dir" != "" ]; then
            export PATH=$neo_dir/bin:$PATH

            #Bring /usr/bin/ocloc to the front to use the new ocloc for ATS.
            export PATH=/usr/bin/:$PATH
            export LD_LIBRARY_PATH=/usr/lib64/:$LD_LIBRARY_PATH
        fi

        # Disable OpenCL support for hwloc
        config_opt+=( --disable-opencl)
    fi

    if [ "$ze_native" != "" ]; then
        config_opt+=( --enable-ze-native=${ze_native} )
    fi

    # Set fabric path after L0, so libfabric is picked from here instead of /usr/lib64
    # Lets see if this breaks the ocloc path
    if [ "$ofi_prov" = "sockets" ]; then
        if [ "$daos" = "yes" ]; then
            # set paths for daos
            export PATH=$DAOS_INSTALL_DIR/bin/:$PATH
            export LD_LIBRARY_PATH=$DAOS_INSTALL_DIR/lib/:$DAOS_INSTALL_DIR/lib64/:$LD_LIBRARY_PATH
        fi
        export LD_LIBRARY_PATH=/opt/intel/csr/ofi/sockets-dynamic/lib/:$LD_LIBRARY_PATH
        config_opt+=( --enable-psm2=no )
    fi

    # Since libfabric is dynamically linked, this should be ok for building.
    if [ "$ofi_prov" = "cxi" ]; then
        export LD_LIBRARY_PATH=/opt/intel/csr/ofi/sockets-dynamic/lib/:$LD_LIBRARY_PATH
        config_opt+=( --enable-psm2=no )
    fi

    # Set the path for psm2 again as well
    if [ "$ofi_prov" = "psm2" ]; then
        export LD_LIBRARY_PATH=/opt/intel/csr/ofi/$ofi_prov-dynamic/lib/:$LD_LIBRARY_PATH
    fi

    # This combination with ze and verbs is unlikely right now, but can come up in
    # newer systems
    if [ "$ofi_prov" = "verbs;ofi_rxm" ]; then
        export LD_LIBRARY_PATH=/opt/intel/csr/ofi/verbs-dynamic/lib/:$LD_LIBRARY_PATH
    fi

    if [ "${compiler}" = "gnu" ]; then
        module load gnu9
    fi

    $src_dir/configure -C --prefix="$install_dir" --disable-perftest ${config_opt[@]} \
        MPICHLIB_CFLAGS="$MPICHLIB_CFLAGS" MPICHLIB_CXXFLAGS="$MPICHLIB_CXXFLAGS" MPICHLIB_FCFLAGS="$MPICHLIB_FCFLAGS" MPICHLIB_F77FLAGS="$MPICHLIB_F77FLAGS" MPICHLIB_LDFLAGS="$MPICHLIB_LDFLAGS" \
        2>&1 | tee c.txt

    #A hack to elimiate dependancy issue with icc RPMs. We need to find a better fix
    if [ "${compiler}" = "icc" ]; then
       cd $src_dir
       for i in -limf -lirng -lcilkrts -lintlc -lsvml; do echo $i; sed -i -e "s/$i//g" libtool; done
       cd -
    fi

    make -j$N_MAKE_JOBS 2>&1 | tee m.txt
    if test "${PIPESTATUS[0]}" != "0"; then
        CollectResults
        exit 1
    fi

    make -j$N_MAKE_JOBS install 2>&1 | tee mi.txt
    if test "${PIPESTATUS[0]}" != "0"; then
        CollectResults
        exit 1
    fi

    #Show libraries linked dynamically
    ldd "$install_dir"/lib/libmpi.so
    cat m.txt | $src_dir/maint/clmake > filtered-make.txt 2>&1
fi

#####################################################################
## Prepare tests
#####################################################################

if [ "$build_tests" == "yes" ]; then
    #Create test binaries here
    #In case of multinode testing, this will allow us to transfer them to
    #the second compute node
    cd test/mpi/
    make -j$N_MAKE_JOBS
    if test "${PIPESTATUS[0]}" != "0"; then
        CollectResults
        exit 1
    fi
    cd -
fi

if [[ -x ${WORKSPACE}/set-xfail.sh ]] ; then
    set_xfail=${WORKSPACE}/set-xfail.sh
elif [[ -x ${SCRIPT_DIR}/set-xfail.sh ]] ; then
    set_xfail=${SCRIPT_DIR}/set-xfail.sh
fi

if [[ -x ${set_xfail} ]] ; then
    if [[ "x$xfail_file" == "x" ]]; then
        xfail_file="${JENKINS_DIR}/xfail.conf"
    fi
fi

# escape the string for non-alpha characters
printf -v ofi_prov_esp "%q" $ofi_prov
cat >populate-testlists.sh<<EOF
#!/bin/bash

# Testlist preparation script autogenerated by test-worker.sh

if [ ! -d test/mpi ]; then
    echo "Run this script at the top of MPICH build directory."
    exit 1
fi

cd test/mpi

if [ ! -x ./config.status ]; then
    echo "./config.status not found or executable"
    exit 1
fi

srcdir=\`grep ^srcdir= config.status | sed -e 's/srcdir=//' -e "s/'//g"\`

if [ "\$srcdir" = "" ]; then
    echo "srcdir not defined in config.log"
    exit 1
fi

if [ "readlink -f \$srcdir" != "readlink -f ." ]; then
    # We are in a VPATH build
    # First, populate testlist

    # Regenerate testlists
    ./config.status

    dirs=\`find -type d | grep -v '/\.'\`

    # Copy testlists not generated by the configure
    for d in \$dirs; do
        if [ ! -f \$d/testlist -a -f \$srcdir/\$d/testlist ]; then
            cmd="cp \$srcdir/\$d/testlist \$d/"
            echo "\$cmd"
            \$cmd
        fi
    done
fi

cd -

${set_xfail} -j ${BUILD_MODE} -c ${compiler} -o ${jenkins_configure} \
    -s ${direct} -m ${ofi_prov_esp} -a ${force_am} -p ${use_pmix} -f ${xfail_file}
EOF

chmod +x ./populate-testlists.sh

# If test is not requested, don't run populate-testlists.sh but leave it.
# This will give users a choice between running tests with and without
# xfails.
# If a user wants, they can later manually run populate-testlists.sh
# to set up xfail-applied testlists.
# (If they don't need xfails, they can simply go to the test directory
# and type `make testing`.)

if [ "$run_tests" == "yes" ]; then
    #####################################################################
    ## Run tests
    #####################################################################

    if [[ -x ${set_xfail} ]] ; then
        ./populate-testlists.sh
    fi

    # Preparation
    case "$jenkins_configure" in
        "async")
            MPIR_CVAR_ASYNC_PROGRESS=1
            export MPIR_CVAR_ASYNC_PROGRESS
            ;;
        "multithread")
            MPIR_CVAR_DEFAULT_THREAD_LEVEL=MPI_THREAD_MULTIPLE
            export MPIR_CVAR_DEFAULT_THREAD_LEVEL
            ;;
    esac

    # run only the minimum level of datatype tests when it is per-commit job
    if [[ "$BUILD_MODE" = "per-commit" || "$BUILD_MODE" = "per-commit-a20" || "$ofi_prov" = "psm2" || "$ofi_prov" = "verbs;ofi_rxm" ]]; then
        MPITEST_DATATYPE_TEST_LEVEL=min
        export MPITEST_DATATYPE_TEST_LEVEL
    fi

    export MPITEST_TIMEOUT_MULTIPLIER=$test_multiplier
    export MPITEST_MAXBUFFER=268435456 # Match main with max buffer size for dtpool tests

    if [ "$compiler" = "icc" ]; then
        if [ -d /opt/intel/inteloneapi/compiler ]; then
            export PATH=/opt/intel/inteloneapi/compiler/latest/linux/bin/intel64/:${PATH#*/mpi/intel64/bin:}:/bin
            export LD_LIBRARY_PATH=/opt/intel/inteloneapi/compiler/latest/linux/compiler/lib/intel64_lin/:${LD_LIBRARY_PATH#*/mpi/intel64/lib:}
        elif [ -d /opt/intel/oneapi/compiler ]; then
            export PATH=/opt/intel/oneapi/compiler/latest/linux/bin/intel64/:${PATH#*/mpi/intel64/bin:}:/bin
            export LD_LIBRARY_PATH=/opt/intel/oneapi/compiler/latest/linux/compiler/lib/intel64_lin/:${LD_LIBRARY_PATH#*/mpi/intel64/lib:}
        fi
    fi

    if [ "$ofi_prov" = "sockets" -a "$daos" = "yes" ]; then
        export LD_LIBRARY_PATH=/opt/intel/csr/ofi/sockets-dynamic/lib/:$DAOS_INSTALL_DIR/lib/:$DAOS_INSTALL_DIR/lib64/:$LD_LIBRARY_PATH
    else
        export LD_LIBRARY_PATH=$ofi_dir/lib/:$LD_LIBRARY_PATH
    fi

    # There is a MR Cache Registration issue in libfabric which needs to be resolved before we
    # get rid of this variable. Until then this variable needs to be exported to avoid any
    # collective test failures.
    if [[ "$ofi_prov" = "verbs;ofi_rxm" ]]; then
        export FI_MR_CACHE_MAX_COUNT=0
    fi

    if [ "$ze_dir" != "" ]; then
        export LD_LIBRARY_PATH=${ze_dir}/lib64:$LD_LIBRARY_PATH
    fi

    if [ "$use_json" == "yes" ]; then
        export MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE="${JENKINS_DIR}/json-files/CH4_coll_tuning.json"
        export MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE="${JENKINS_DIR}/json-files/MPIR_Coll_tuning.json"
        export MPIR_CVAR_COLL_POSIX_SELECTION_TUNING_JSON_FILE="${JENKINS_DIR}/json-files/POSIX_coll_tuning.json"
    fi
    export FI_PROVIDER="$ofi_prov"

    echo $PATH
    echo $LD_LIBRARY_PATH
    if [[ "$force_am" = "am" && "$jenkins_configure" = "debug" ]]; then
        export MPIR_CVAR_CH4_OFI_ENABLE_RMA=0
        export MPIR_CVAR_CH4_OFI_ENABLE_TAGGED=0
    fi

    if [ "$use_pmix" = "pmix" ]; then
        export LD_LIBRARY_PATH=$pmix_dir/lib:$prte_dir/lib:$LD_LIBRARY_PATH
        export PATH=$pmix_dir/bin:$prte_dir/bin:$PATH
    fi

    echo `env | grep MPI`
    if [ "$ofi_prov" == "opa1x" ]; then
         make testing V=1 MPITEST_PROGRAM_WRAPPER="-genv FI_OPA1X_UUID \`uuidgen\` -ppn 1 "
    elif [[ "$BUILD_MODE" = "multinode" ]]; then
         make testing MPITEST_PROGRAM_WRAPPER="-ppn 1 "
    else
        if [ "$use_pmix" = "pmix" ]; then
            make testing MPIEXEC="/opt/prrte/bin/prte" MPITEST_PROGRAM_WRAPPER="--map-by :OVERSUBSCRIBE"
        else
            make testing
        fi
    fi

    if test -z "`cat filtered-make.txt`" ; then
        failures=0
    else
        failures=1
    fi

    # Delete the last line of the test file and add the warning tests
    sed -i '$ d' test/mpi/summary.junit.xml

    echo "    <testsuite" >> test/mpi/summary.junit.xml
    echo "        failures=\"$failures\"" >> test/mpi/summary.junit.xml
    echo "        errors=\"0\"" >> test/mpi/summary.junit.xml
    echo "        skipped=\"0\"" >> test/mpi/summary.junit.xml
    echo "        tests=\"1\"" >> test/mpi/summary.junit.xml
    echo "        date=\"`date +%Y-%m-%d-%H-%M`\"" >> test/mpi/summary.junit.xml
    echo "        name=\"summary_junit_xml\">" >> test/mpi/summary.junit.xml

    echo "        <testcase name=\"compilation\" time=\"0\">" >> test/mpi/summary.junit.xml

    if [ "$failures" != "0" ] ; then
      echo "            <failure><![CDATA[" >> test/mpi/summary.junit.xml
      cat filtered-make.txt >> test/mpi/summary.junit.xml
      echo "            ]]></failure>" >> test/mpi/summary.junit.xml
    fi

    echo "        </testcase>" >> test/mpi/summary.junit.xml
    echo "    </testsuite>" >> test/mpi/summary.junit.xml
    echo "</testsuites>" >> test/mpi/summary.junit.xml

    # Cleanup
    if killall -9 hydra_pmi_proxy; then
        echo "leftover hydra_pmi_proxy processes killed"
    fi
fi

#####################################################################
## Copy Test results and Cleanup
#####################################################################

CollectResults

# Coverage
#if [[ "$jenkins_configure" = "debug" && ("$compiler" = "gnu" || "$compiler" = "gnu-8") ]]; then
#    set -x
#    cd $WORKSPACE
#    make coverage
#    lcov --directory . --capture --output-file app.info
#    python lcov_cobertura.py app.info
#    cp coverage.xml test/mpi/
#    cd -
#fi

exit 0

