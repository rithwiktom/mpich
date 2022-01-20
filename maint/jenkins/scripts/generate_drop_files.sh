#!/bin/bash

function generate_lua_script {
    provider="$1"
    compiler="$2"
    configs="$3"
    DROP_VERSION="$4"
    pmix="$5"
    flavor="$6"
    debug="$7"

    debug_string=""
    deterministic_text=""
    deterministic_results=""
    if [ "$debug" != "" ]; then
        debug_string="-${debug}"

        if [ "$debug" == "deterministic" ]; then
            deterministic_text=" that should produce deterministic results"
            deterministic_results=", deterministic results"
        fi
    fi

    pmix_string=""
    if [ "$pmix" == "pmix" ]; then
        pmix_string="-pmix"
    fi

    flavor_string=""
    if [ "$flavor" != "regular" ]; then
        flavor_string="-${flavor}"
    fi

    mkdir -p ${MODULEFILE_DIR}/${compiler}-${provider}${debug_string}${pmix_string}${flavor_string}
    filename="${MODULEFILE_DIR}/${compiler}-${provider}${debug_string}${pmix_string}${flavor_string}/${version}.${release}.lua"

    provider_string="${provider}"
    if [ "$provider" == "verbs" ]; then
        provider_string="verbs;ofi_rxm"
    fi

    cat > $filename << EOF
help([[
   This module loads MPICH with $compiler compiler ($configs build)${deterministic_text}

   Documentation for tuning parameters is located at: /usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/share/doc/mpich/TUNING_PARAMETERS
   RELEASE_NOTES for this release is located at: /usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/share/doc/mpich/RELEASE_NOTES
EOF

    if [ "$compiler" == "icc" ]; then
        cat >> $filename << EOF
   Intel compiler is a prerequisite.
EOF
    fi

    cat >> $filename << EOF

]])

whatis("Name: MPICH ")
whatis("Version:  $DROP_VERSION ")
whatis("Category: library, runtime support ")
whatis("Description: MPICH library for $compiler compiler ($configs build${deterministic_results})")

EOF

    if [ "$debug" == "deterministic" ]; then
        cat >> $filename << EOF
pushenv("MPIR_CVAR_ALLREDUCE_DEVICE_COLLECTIVE", "0")
pushenv("MPIR_CVAR_REDUCE_DEVICE_COLLECTIVE", "0")

EOF
    fi

    if [ "$flavor" != "nogpu" ]; then
        cat >> $filename << EOF
pushenv("ZE_ENABLE_PCI_ID_DEVICE_ORDER", "1")
pushenv("EngineInstancedSubDevices", "0")

EOF
    fi

#    if [ "$compiler" == "icc" -a "$flavor" == "default" ]; then
#        cat >> $filename << EOF
#prereq("oneapi")
#
#EOF
#    fi

    cat >> $filename << EOF
unsetenv("FI_PROVIDER_PATH")

family("MPI")

prepend_path("LIBRARY_PATH","/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/lib")
prepend_path("LD_LIBRARY_PATH","/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/lib")
prepend_path("PATH","/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/bin")
prepend_path("CPATH","/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/include")

pushenv("MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE", "/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/json-files/CH4_coll_tuning.json")
pushenv("MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE", "/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/json-files/MPIR_Coll_tuning.json")
pushenv("MPIR_CVAR_COLL_POSIX_SELECTION_TUNING_JSON_FILE", "/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/json-files/POSIX_coll_tuning.json")
EOF

    if [ "$provider" != "all" ]; then
    cat >> $filename << EOF
pushenv("FI_PROVIDER", "${provider_string}")
pushenv("PSM3_MULTI_EP", "1")
EOF
    fi

    if [ "$provider" == "psm2" -a "$flavor" == "regular" ]; then
        cat >> $filename << EOF
pushenv("MPIR_CVAR_ENABLE_GPU", "0")
EOF
    fi

}

# For the JLSE nodes that use TCL modulefiles instead of LUA
function generate_tcl_script {
    provider="$1"
    compiler="$2"
    configs="$3"
    DROP_VERSION="$4"
    pmix="$5"
    flavor="$6"
    debug="$7"

    debug_string=""
    deterministic_text=""
    deterministic_results=""
    if [ "$debug" != "" ]; then
        debug_string="-${debug}"

        if [ "$debug" == "deterministic" ]; then
            deterministic_text=" that should produce deterministic results"
            deterministic_results=", deterministic results"
        fi
    fi

    pmix_string=""
    if [ "$pmix" == "pmix" ]; then
        pmix_string="-pmix"
    fi

    flavor_string=""
    if [ "$flavor" != "regular" ]; then
        flavor_string="-${flavor}"
    fi

    mkdir -p ${MODULEFILE_DIR}/${compiler}-${provider}${debug_string}${pmix_string}${flavor_string}
    filename="${MODULEFILE_DIR}/${compiler}-${provider}${debug_string}${pmix_string}${flavor_string}/${version}.${release}.tcl"

    provider_string="${provider}"
    if [ "$provider" == "verbs" ]; then
        provider_string="verbs;ofi_rxm"
    fi

    cat > $filename << EOF
#%Module
#
# advisor module
#

proc ModulesHelp { } {
   puts stderr "    MPICH library for $compiler compiler ($configs build${deterministic_results})"
   puts stderr "    This module loads MPICH with $compiler compiler ($configs build)${deterministic_text}"
   puts stderr "    Documentation for tuning parameters is located at: /usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/share/doc/mpich/TUNING_PARAMETERS"
   puts stderr "    RELEASE_NOTES for this release is located at: /usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION/share/doc/mpich/RELEASE_NOTES"
EOF

    if [ "$compiler" == "icc" ]; then
        cat >> $filename << EOF
   puts stderr "    Intel compiler is a prerequisite."
EOF
    fi

    cat >> $filename << EOF
}

set VERSION "$DROP_VERSION"

EOF

    if [ "$debug" == "deterministic" ]; then
        cat >> $filename << EOF
setenv {MPIR_CVAR_ALLREDUCE_DEVICE_COLLECTIVE} {0}
setenv {MPIR_CVAR_REDUCE_DEVICE_COLLECTIVE} {0}

EOF
    fi

#    if [ "$compiler" == "icc" -a "$flavor" == "default" ]; then
#        cat >> $filename << EOF
#prereq("oneapi")
#
#EOF
#    fi

MPI_DIR="/usr/mpi/mpich-ofi-$provider-$compiler-$configs${pmix_string}${flavor_string}-$DROP_VERSION"

    cat >> $filename << EOF
unsetenv {FI_PROVIDER_PATH}

prepend-path {LIBRARY_PATH} "${MPI_DIR}/lib"
prepend-path {LD_LIBRARY_PATH} "${MPI_DIR}/lib"
prepend-path {PATH} "${MPI_DIR}/bin"
prepend-path {CPATH} "${MPI_DIR}/include"

setenv {MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE} "${MPI_DIR}/json-files/CH4_coll_tuning.json"
setenv {MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE} "${MPI_DIR}/json-files/MPIR_Coll_tuning.json"
setenv {MPIR_CVAR_COLL_POSIX_SELECTION_TUNING_JSON_FILE} "${MPI_DIR}/json-files/POSIX_coll_tuning.json"
EOF

    if [ "$provider" != "all" ]; then
    cat >> $filename << EOF
setenv {FI_PROVIDER} "${provider_string}"
setenv {PSM3_MULTI_EP} "1"
EOF
    fi


    if [ "$provider" == "psm2" -a "$flavor" == "regular" ]; then
        cat >> $filename << EOF
setenv {MPIR_CVAR_ENABLE_GPU} {0}
EOF
    fi

}

set -x

REMOTE_WS="$1"
JENKINS_DIR="$2"
provider="$3"
compiler="$4"
configs="$5"
pmix="$6"
flavor="$7"

version=$(<$JENKINS_DIR/drop_version)
DROP_VERSION=drop${version}

release=$(<$JENKINS_DIR/release_version)

# Generate mpich.sh
cat > $REMOTE_WS/mpich.sh << EOF
#!/bin/bash

drop=$DROP_VERSION
provider=$provider
EOF
cat >> $REMOTE_WS/mpich.sh << "EOF"
compiler=$1

if [ -z "$1" ]; then
    echo "Usage: \"source mpich.sh <compiler>\". Enter gnu or icc compiler"
    exit 0
fi

if [ "$compiler" = "icc" ]; then
  #load intel compiler
  if [ -f /opt/intel/inteloneapi/compiler ]; then
    . /opt/intel/inteloneapi/compiler/latest/env/vars.sh intel64
  elif [ -f /opt/intel/oneapi/compiler ]; then
    . /opt/intel/oneapi/compiler/latest/env/vars.sh intel64
  fi
fi

# Clear the env variable that the intel compilers may set.
unset FI_PROVIDER_PATH

export LIBRARY_PATH=/usr/mpi/mpich-ofi-$provider-$compiler-default-$drop/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}
export PATH=/usr/mpi/mpich-ofi-$provider-$compiler-default-$drop/bin:$PATH
export LD_LIBRARY_PATH=/usr/mpi/mpich-ofi-$provider-$compiler-default-$drop/lib:$LD_LIBRARY_PATH

export MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE=/usr/mpi/mpich-ofi-$provider-$compiler-default-$drop/json-files/CH4_coll_tuning.json
export MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE=/usr/mpi/mpich-ofi-$provider-$compiler-default-$drop/json-files/MPIR_Coll_tuning.json
EOF

# Generate module files
MODULEFILE_DIR=$REMOTE_WS/modulefiles/mpich
mkdir -p $MODULEFILE_DIR

if [ "$configs" = "debug" ]; then
    generate_tcl_script $provider $compiler $configs $DROP_VERSION $pmix $flavor "debug"
    generate_lua_script $provider $compiler $configs $DROP_VERSION $pmix $flavor "debug"
    generate_tcl_script $provider $compiler $configs $DROP_VERSION $pmix $flavor "deterministic"
    generate_lua_script $provider $compiler $configs $DROP_VERSION $pmix $flavor "deterministic"
else
    generate_tcl_script $provider $compiler $configs $DROP_VERSION $pmix $flavor ""
    generate_lua_script $provider $compiler $configs $DROP_VERSION $pmix $flavor ""
fi
