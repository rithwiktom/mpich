import java.util.regex.*
import com.cloudbees.groovy.cps.NonCPS
import org.jenkinsci.plugins.workflow.steps.*

def tarball_name = "mpich-nightly.tar.bz2"
def continue_pipeline = true
currentBuild.result = "SUCCESS"

/* Configure ofi-domain for odd days */
ofi_domain = ""
def date = new Date()
def day = date[Calendar.DAY_OF_YEAR]

if (day % 2 == 0) {
    ofi_domain = "no"
} else {
    ofi_domain = "yes"
}

/*
  Possible values for each configure group
  If the regex is updated, these also need to be updated
*/
def all_netmods   = [ "ofi" ]
def all_providers = [ "sockets", "psm2", "verbs", "psm3" ]
def all_compilers = [ "gnu", "icc" ]
def all_ams       = [ "am", "noam" ]
def all_directs   = [ "netmod", "auto", "no-odd-even" ]
def all_configs   = [ "debug", "default" ]
def all_gpus      = [ "nogpu", "ats" ]
def all_tests     = [ "cpu-gpu", "gpu" ]
def all_threads   = [ "runtime", "handoff", "direct", "lockless" ]
def all_vcis      = [ "vci1", "vci4" ]
def all_asyncs    = [ "async-single", "async-multiple" ]
def all_pmixs     = [ "pmix", "nopmix" ]

/* Filter out configurations based on the type of nightly being run */
if ("${RUN_TYPE}" == "regular") {
    all_gpus = [ "nogpu" ]
    all_threads = [ "runtime" ]
    all_vcis = [ "vci1" ]
    all_asyncs = [ "async-single" ]
} else if ("${RUN_TYPE}" == "vci") {
    all_providers = [ "sockets", "psm2" ]
    all_gpus = [ "nogpu" ]
    all_threads = [ "handoff", "direct", "lockless" ]
} else if ("${RUN_TYPE}" == "weekly-opt") {
    all_providers = [ "sockets", "psm2" ]
    all_ams = [ "noam" ]
    all_directs = [ "auto" ]
    all_configs = [ "opt" ]
    all_gpus = [ "nogpu" ]
    all_threads = [ "runtime" ]
    all_vcis = [ "vci1" ]
    all_asyncs = [ "async-single" ]
} else if ("${RUN_TYPE}" == "ats") {
    all_providers = [ "sockets", "psm3" ]
    all_compilers = [ "gnu" ]
    all_gpus = [ "ats" ]
    all_tests = [ "gpu" ]
    all_threads = [ "runtime" ]
    all_vcis = [ "vci1" ]
    all_asyncs = [ "async-single" ]
}

/* Filter out invalid configurations */
def invalid_config(netmod, provider, compiler, am, direct, config, gpu, test, thread, vci, async, pmix)
{
    invalid = false

    // GPU filters
    invalid |= ("${test}" == "gpu" && "${gpu}" == "nogpu")
    invalid |= ("${provider}" == "psm2" && "${gpu}" != "nogpu")
    invalid |= ("${thread}" != "runtime" && "${gpu}" != "nogpu")

    // PMIx filters
    invalid |= ("${pmix}" == "pmix" && "${provider}" != "sockets")

    // AM filters
    invalid |= ("${am}" == "am" && "${gpu}" != "nogpu")
    invalid |= ("${am}" == "am" && "${thread}" != "runtime")

    // Threading filters
    invalid |= ("${thread}" == "runtime" && "${vci}" != "vci1")

    return invalid
}

def skip_config(netmod, provider, compiler, am, direct, config, gpu, test, thread, vci, async, pmix)
{
    skip = false

    // Misc
    skip |= ("${pmix}" == "pmix") // Don't nightly test pmix
    skip |= ("${am}" == "am") // TODO: Skip am until failures resolved

    // GPUs
    skip |= ("${gpu}" != "nogpu" && "${test}" == "cpu-gpu") // Only do GPU testing on GPU systems since its already slow

    // Threading
    skip |= ("${thread}" == "handoff") // Don't nightly test handoff
    skip |= ("${thread}" != "runtime" && "${provider}" == "psm2" && "${vci}" == "vci4") // Lots of failures in psm2 + vci4
    skip |= ("${thread}" != "runtime" && "${async}" == "async-single") // Only test async-multiple
    skip |= ("${thread}" != "runtime" && "${provider}" == "verbs") // Only test psm2 and sockets with threading
    skip |= ("${thread}" == "runtime" && "${async}" != "async-single") // Only test async-single with runtime mode

    // Provider
    skip |= ("${provider}" == "verbs" && "${gpu}" == "nogpu") // TODO: Skip because of anccskl6 cluster issues

    return skip
}

/* Grab all of the nodes in a specific label */
@NonCPS
def get_nodes(label) {
    def nodes = jenkins.model.Jenkins.get().computers
      .findAll{ it.node.labelString.contains(label) }
      .collect{ it.node.selfLabel.name }
    return nodes
}

/* Check if specific node is offline */
@NonCPS
def check_node_offline(name) {
    return jenkins.model.Jenkins.get().getComputer(name).isOffline()
}

/* Get the nodes from the "tester_pool" label */
def tester_pool_nodes = "" + get_nodes("tester_pool").join(" || ")

def branches = [:]

for (a in all_netmods) {
    for (b in all_providers) {
        for (c in all_compilers) {
            for (d in all_ams) {
                for (e in all_directs) {
                    for (f in all_configs) {
                        for (g in all_gpus) {
                            for (h in all_tests) {
                                for (i in all_threads) {
                                    for (j in all_vcis) {
                                        for (k in all_asyncs) {
                                            for (l in all_pmixs) {
                                                def netmod = a
                                                def provider = b
                                                def compiler = c
                                                def am = d
                                                def direct = e
                                                def config = f
                                                def gpu = g
                                                def test = h
                                                def thread = i
                                                def vci = j
                                                def async = k
                                                def pmix = l

                                                /* Filter out the invalid configurations */
                                                if (invalid_config(netmod, provider, compiler, am, direct, config, gpu, test, thread, vci, async, pmix)) {
                                                    continue
                                                }

                                                /* Filter out configurations to skip */
                                                if (skip_config(netmod, provider, compiler, am, direct, config, gpu, test, thread, vci, async, pmix)) {
                                                    continue
                                                }

                                                /* Define the stage for each given configuration */
                                                branches["${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"] = {
                                                    def config_name = "${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"
                                                    def node_name = tester_pool_nodes
                                                    def username = "sys_csr1"
                                                    def build_mode = "nightly"

                                                    /* Set the current node and username depending on the configuration */
                                                    if ("${provider}" == "verbs" || "${provider}" == "psm3") {
                                                        node_name = "anccskl6"
                                                    }
                                                    if ("${gpu}" == "ats") {
                                                        node_name = "jfcst-xe"
                                                        build_mode = "nightly-gpu"
                                                    }
                                                    /* Throw an exception if the compute resources are offline */
                                                    if (node_name != tester_pool_nodes) {
                                                        if (check_node_offline(node_name)) {
                                                            def errstr = "node '${node_name}' is offline"
                                                            print errstr
                                                            throw new Exception(errstr);
                                                        }
                                                    } else {
                                                        def offline_count = 0
                                                        for (node in get_nodes("tester_pool")) {
                                                            if (check_node_offline(node)) {
                                                                offline_count = offline_count + 1
                                                            }
                                                        }
                                                        if (offline_count == get_nodes("tester_pool").size()) {
                                                            def errstr = "all nodes in label 'tester_pool' are offline"
                                                            print errstr
                                                            throw new Exception(errstr);
                                                        }
                                                    }
                                                    node("${node_name}") {
                                                        cleanWs()
                                                        sh "mkdir -p ${config_name}"
                                                        unstash name: 'nightly-tarball'
                                                        sh(script: """
#!/bin/bash -x

# Print out the hostname for debugging logs
hostname

cat > nightly-test-job.sh << "EOF"
#!/bin/bash -x

# Set overlap as default
export SLURM_OVERLAP=1

srun -N 1 hostname

set +e
srun --chdir="/tmp" rm -rf /tmp/
srun --chdir="/dev/shm" rm -rf /dev/shm/
set -e

PRE="/state/partition1/home/${username}/"
REL_WORKSPACE="\${WORKSPACE#\$PRE}"
OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"
REMOTE_WS=\$(srun --chdir=/tmp mktemp -d /tmp/jenkins.tmp.XXXXXXXX)
JENKINS_DIR="\$REMOTE_WS/maint/jenkins"
BUILD_SCRIPT_DIR="\$JENKINS_DIR/scripts"

sbcast ${tarball_name} "\${REMOTE_WS}/${tarball_name}"
srun --chdir="\$REMOTE_WS" tar -xf ${tarball_name}

CONFIG_EXTRA=""
embedded_ofi="no"
xpmem="yes"
gpudirect="yes"
n_jobs=32
ze_native=""
neo_dir=""
ze_dir=""
xpmem_dir="/usr/local"
fast=""
ofi_domain="${ofi_domain}"

disable_psm2="no"

thread_cs="per-vci"
mt_model="runtime"

if [ "${config}" = "debug" ]; then
    fast="none"
else
    fast="avx"
fi

# Set common multi-threading environment (if enabled)
# identify the actual threading model
runtime_mt_model="direct"
if [ "${thread}" != "runtime" ]; then
   runtime_mt_model="${thread}"
fi

# finalize threading model selection type
if [ "${config}" = "debug" ]; then
    mt_model="runtime"
fi

if [ "\${mt_model}" = "runtime" ]; then
   export MPIR_CVAR_CH4_MT_MODEL=\$runtime_mt_model
fi

nvcis=`echo ${vci} | sed -e 's/^vci//'`
export MPIR_CVAR_CH4_NUM_VCIS=\${nvcis}
export MPIR_CVAR_CH4_OFI_MAX_RMA_SEP_CTX=\${nvcis}
export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=\${nvcis}
export MPIR_CVAR_ASYNC_PROGRESS=0

if [ "${thread}" = "handoff" ]; then
    export MPIR_CVAR_ASYNC_PROGRESS=1
fi

echo "Appending mt_xfail_common.conf"
srun --chdir="\$REMOTE_WS" /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
srun --chdir="\$REMOTE_WS" /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_common.conf >> \$JENKINS_DIR/xfail.conf"

if [ "${vci}" = "vci4" ]; then
    echo "Appending mt_xfail_vci4.conf"
    srun --chdir="\$REMOTE_WS" /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
    srun --chdir="\$REMOTE_WS" /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_vci4.conf >> \$JENKINS_DIR/xfail.conf"
fi

echo "Appending mt_xfail_\${runtime_mt_model}.conf"
srun --chdir="\$REMOTE_WS" /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
srun --chdir="\$REMOTE_WS" /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_\${runtime_mt_model}.conf >> \$JENKINS_DIR/xfail.conf"

if [ "${async}" = "async-single" ]; then
    export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=1
fi

if [ "${provider}" = "psm2" ]; then
    export FI_PSM2_LOCK_LEVEL=1
elif [ "${provider}" = "psm3" ]; then
    export PSM3_MULTI_EP=1
fi

CONFIG_EXTRA="\$CONFIG_EXTRA --disable-spawn --with-ch4-max-vcis=\${nvcis}"

# Set the environment for GPU systems
if [ "$gpu" = "ats" ]; then
    embedded_ofi="yes"
    xpmem="no"
    # TODO: Switch back to system-installed neo once memid impl is fixed
    neo_dir=/home/gengbinz/drivers.gpu.compute.runtime/workspace-09-10-2021
    ze_dir=/usr
    ze_native="$gpu"
    disable_psm2="yes"
    CONFIG_EXTRA="\$CONFIG_EXTRA --enable-psm3"
elif [ "$gpu" = "nogpu" ]; then
    gpudirect="no"
    CONFIG_EXTRA="\$CONFIG_EXTRA --without-ze"
fi

# AM builds force direct mode with global locking
if [ "${am}" = "am" ]; then
    thread_cs="global"
    mt_model="direct"
fi

NAME="${config_name}"

export LD_LIBRARY_PATH=\$OFI_DIR/lib/:\$LD_LIBRARY_PATH

srun --chdir="\$REMOTE_WS" /bin/bash \${BUILD_SCRIPT_DIR}/test-worker.sh \
    -B \${disable_psm2} \
    -h \${REMOTE_WS} \
    -i \${OFI_DIR} \
    -c ${compiler} \
    -o ${config} \
    -F \${fast} \
    -d ${am} \
    -b ${build_mode} \
    -s ${direct} \
    -p ${provider} \
    -P ${pmix} \
    -l "\${thread_cs}" \
    -m \${n_jobs} \
    -N "\${neo_dir}" \
    -r \$REL_WORKSPACE/\${NAME} \
    -t 2.0 \
    -k "\${embedded_ofi}" \
    -M "\${mt_model}" \
    -X "\${xpmem_dir}" \
    -H "\${gpudirect}" \
    -Y "\${ze_native}" \
    -Z "\${ze_dir}" \
    -G ${test} \
    -z "-L\$neo_dir/lib64" \
    -E \$xpmem \
    -O \$ofi_domain \
    -j "\$CONFIG_EXTRA"

EOF

chmod +x nightly-test-job.sh
salloc -J nightly:${provider}:${compiler}:${am}:${direct}:${config}:${gpu}:${test}:${thread}:${vci}:${async}:${pmix} -N 1 -t 360 ./nightly-test-job.sh
""")
                                                        archiveArtifacts "$config_name/**"
                                                        junit skipPublishingChecks: true, testResults: "${config_name}/test/mpi/summary.junit.xml"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

node(tester_pool_nodes) {
    if (continue_pipeline) {
        try {
            /* Checkout the repository */
            stage('Checkout') {
                cleanWs()

                // Get some code from a GitHub repository
                checkout([$class: 'GitSCM',
                          branches: [[name: '*/integration']],
                          doGenerateSubmoduleConfigurations: false,
                          extensions: [
                              [$class: 'SubmoduleOption',
                                  disableSubmodules: false,
                                  recursiveSubmodules: true
                              ]],
                          submoduleCfg: [],
                          userRemoteConfigs: [[
                              credentialsId: 'password-sys_csr1_github',
                              url: 'https://github.com/intel-innersource/libraries.runtimes.hpc.mpi.mpich-aurora.git'
                          ]]
                         ])
                    sh(script: """
git submodule sync
git submodule update --init --recursive
""")
            }
        } catch (FlowInterruptedException err) {
            print err.toString()
            currentBuild.result = "ABORTED"
            continue_pipeline = false
        } catch (Exception err) {
            print err.toString()
            currentBuild.result = "FAILURE"
            continue_pipeline = false
        }
    }
    if (continue_pipeline) {
        try {
            /* Run autogen */
            stage('Autogen') {
                sh(script: """
#!/bin/bash

set -ex

AUTOTOOLS_DIR="\$HOME/software/autotools/bin"

if [ ! -d \$HOME/software ] ; then
    exit 1;
fi

./autogen.sh --with-autotools=\$AUTOTOOLS_DIR --without-ucx | tee a.txt

if [ ! -f ./configure ]; then
    exit 1;
fi

cd test/mpi

./autogen.sh --with-autotools=\$AUTOTOOLS_DIR | tee test-a.txt

if [ ! -f ./configure ]; then
    exit 1;
fi

cd -

tar --exclude=${tarball_name} -cjf ${tarball_name} *
""")
                stash includes: 'mpich-nightly.tar.bz2', name: 'nightly-tarball'
                cleanWs()
            }
        } catch (FlowInterruptedException err) {
            print err.toString()
            currentBuild.result = "ABORTED"
            continue_pipeline = false
        } catch (Exception err) {
            print err.toString()
            currentBuild.result = "FAILURE"
            continue_pipeline = false
        }
    }
}

if (continue_pipeline) {
    stage ('Run Tests') {
        try {
            /* Run tests */
            parallel branches
        } catch (FlowInterruptedException err) {
            print err.toString()
            currentBuild.result = "ABORTED"
            continue_pipeline = false
        } catch (Exception err) {
            print err.toString()
            currentBuild.result = "FAILURE"
            continue_pipeline = false
        }
    }
}
