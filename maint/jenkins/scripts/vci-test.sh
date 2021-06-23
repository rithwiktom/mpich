#!/bin/bash

set -x

WORKSPACE="$PWD"
compiler="gnu"
jenkins_configure="default"
direct="netmod"
netmod="ofi"
config_opts=""
ofi_prov=""
ofi_dir="/opt/intel/csr"
force_am="noam"
N_MAKE_JOBS=8
results="$HOME"
test_multiplier=1.0
run_tests="yes"
install_dir="$WORKSPACE/_inst"
src_dir="."
embed_ofi="no"
cpu=""
xfail_file=""
mt_model="direct"
vci="vci1"
async_thread="async-multiple"
optional_args=""
job_type="per-commit"

cmdline="$0"
for a in "$@"; do
    cmdline="$cmdline '$a'"
done

#####################################################################
## Initialization
#####################################################################

while getopts ":b:h:c:d:o:s:n:p:i:m:r:t:x:f:u:j:k:a:w:M:V:Y:" opt; do
    case "$opt" in
	#
	# Pass-through to test-worker.sh
	#
        b)
            job_type=$OPTARG ;;
        h)
            WORKSPACE=$OPTARG ;;
        c)
            compiler=$OPTARG ;;
        d)
            force_am=$OPTARG ;;
        o)
            jenkins_configure=$OPTARG ;;
        s)
            direct=$OPTARG ;;
        n)
            netmod=$OPTARG ;;
        p)
            ofi_prov=$OPTARG
	    optional_args="${optional_args} -p ${ofi_prov}"
	    ;;
        i)
            ofi_dir=$OPTARG ;;
        m)
            N_MAKE_JOBS=$OPTARG ;;
        r)
            results=$OPTARG ;;
        t)
            test_multiplier=$OPTARG ;;
        x)
            run_tests=$OPTARG ;;
        w)
            xfail_file=$OPTARG
	    optional_args="${optional_args} -w ${xfail_file}"
	    ;;
        f)
            install_dir=$OPTARG ;;
        u)
            src_dir=$OPTARG ;;
        j)
            config_opts=$OPTARG ;;
        k)
            embed_ofi=$OPTARG ;;
        a)
            cpu=$OPTARG
	    optional_args="${optional_args} -a ${cpu}"
	    ;;
	#
	# Original parameters added and interpreted in this script
	#
	M)
	    mt_model=$OPTARG ;;
	V)
	    vci=$OPTARG ;;
	Y)
	    async_thread=$OPTARG ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
    esac
done

# Validate parameters
n_vcis=`echo $vci | sed -e 's/^vci//'`
if [ "$n_vcis" == "" ]; then
    echo "Invalid vci specified: should be \"vciX\" where X is an integer."
    exit 1
fi

case "$mt_model" in
    direct|handoff|trylock|lockless)
	build_mt_model=$mt_model;;
    *)
	echo "-M: must be one of {direct|handoff|trylock|lockless}"
	exit 1
esac

case "$async_thread" in
    async-single|async-multiple)
	;;
    *)
	echo "-Y must be either async-single orasync-multiple"
	exit 1
esac

ch4_vci_opts="--disable-spawn"
ch4_vci_opts+=" --with-ch4-max-vcis=${n_vcis}"

if [ "$jenkins_configure" == "debug" ]; then
    export MPIR_CVAR_CH4_MT_MODEL=$mt_model
    build_mt_model="runtime"
fi

# Set runtime CVARs
export MPIR_CVAR_CH4_NUM_VCIS=${n_vcis}
export MPIR_CVAR_CH4_OFI_MAX_RMA_SEP_CTX=${n_vcis}
export MPIR_CVAR_ASYNC_PROGRESS=0
export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=${n_vcis}
if [ "$mt_model" == "handoff" ]; then
    export MPIR_CVAR_ASYNC_PROGRESS=1
fi
if [ "$async_thread" == "async-single" ]; then
    export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=1
fi

if [ "${ofi_prov}" = "psm2" ]; then
    case "${mt_model}" in
	direct|handoff|trylock)
	    export FI_PSM2_LOCK_LEVEL=1;;
	lockless)
	    export FI_PSM2_LOCK_LEVEL=2;;
    esac
fi

mydir=`dirname ${BASH_SOURCE[0]}`

bash $mydir/test-worker.sh \
    -b $job_type \
    -h $WORKSPACE \
    -c $compiler \
    -d ${force_am} \
    -o ${jenkins_configure} \
    -s $direct \
    -n $netmod \
    -i $ofi_dir \
    -m $N_MAKE_JOBS \
    -r $results \
    -t ${test_multiplier} \
    -x ${run_tests} \
    -f ${install_dir} \
    -u ${src_dir} \
    -k ${embed_ofi} \
    -l per-vci \
    -M ${build_mt_model} \
    -j "${ch4_vci_opts} ${config_opts}" \
    ${optional_args}

echo $cmdline > $results/vci-test-cmdline.txt
