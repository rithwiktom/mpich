import java.util.regex.*
import com.cloudbees.groovy.cps.NonCPS
import org.jenkinsci.plugins.workflow.steps.*

def setBuildStatus(String message, String state, String context, String sha, String url) {
    step([
        $class: "GitHubCommitStatusSetter",
        reposSource: [$class: "ManuallyEnteredRepositorySource", url: "https://github.com/intel-innersource/libraries.runtimes.hpc.mpi.mpich-aurora.git"],
        contextSource: [$class: "ManuallyEnteredCommitContextSource", context: context],
        errorHandlers: [[$class: "ChangingBuildStatusErrorHandler", result: "UNSTABLE"]],
        commitShaSource: [$class: "ManuallyEnteredShaSource", sha: sha ],
        statusBackrefSource: [$class: "ManuallyEnteredBackrefSource", backref: "$url/${BUILD_ID}/pipeline"],
        statusResultSource: [$class: "ConditionalStatusResultSource", results: [[$class: "AnyBuildResult", message: message, state: state]] ]
    ]);
}

def tarball_name = "mpich-per-commit-${BUILD_NUMBER}.tar.bz2"
jenkins_configs = []
jenkins_config_string = ""
jenkins_config_extras = ""
jenkins_env_string = ""
jenkins_envs = ""
jenkins_node_string = ""
jenkins_node = ""
def continue_pipeline = true
BLUEOCEAN_URL = "https://ancoral001.an.intel.com/blue/organizations/jenkins/per-commit-mpich/detail/per-commit-mpich"
def status_context = ""
def status_message = "Completed"
currentBuild.result = "SUCCESS"

/*
  Possible values for each configure group
  If the regex is updated, these also need to be updated
*/
def num_groups = 12
def num_required_groups = 7
def num_optional_groups = num_groups - num_required_groups

/* Required: */
def all_netmods   = [ "ofi" ]
def all_providers = [ "sockets", "psm2", "verbs", "cxi", "psm3", "tcp"]
def all_compilers = [ "gnu", "icc" ]
def all_ams       = [ "am", "noam" ]
def all_directs   = [ "netmod", "auto", "no-odd-even" ]
def all_configs   = [ "debug", "default" ]
def all_gpus      = [ "nogpu", "ats" ]
/* Optional: */
def all_tests     = [ "cpu-gpu", "gpu" ]
def all_threads   = [ "runtime", "handoff", "direct", "lockless" ]
def all_vcis      = [ "vci1", "vci4" ]
def all_asyncs    = [ "async-single", "async-multiple" ]
def all_pmixs     = [ "pmix", "nopmix" ]

/* Used for parsing optional arguments (ordering is important) */
def all_optionals = [ all_tests, all_threads, all_vcis, all_asyncs, all_pmixs ]

/* Default values for the optional groups */
def default_test   = "cpu-gpu"
def default_thread = "runtime"
def default_vci    = "vci1"
def default_async  = "async-single"
def default_pmix   = "nopmix"
def all_defaults = [ default_test, default_thread, default_vci, default_async, default_pmix ]

/* Collect invalid configurations */
invalid_configs = []

/* Comment invalid configurations to comment on github as a warning */
def comment_invalid_configs()
{
    if (invalid_configs.size() > 0) {
        def github_comment = """
:warning: The following are invalid configurations for per-commit testing:

```"""
        for (i = 0; i < invalid_configs.size(); ++i) {
            github_comment = github_comment + invalid_configs[i]
        }
        github_comment = github_comment + """
```"""
        githubPRComment comment : githubPRMessage(github_comment)
    }
}

/* Filter out invalid configurations */
def invalid_config(netmod, provider, compiler, am, direct, config, gpu, test, thread, vci, async, pmix)
{
    def invalid = false

    // GPU filters
    invalid |= ("${test}" == "gpu" && "${gpu}" == "nogpu")
    invalid |= ("${provider}" == "verbs" && "${gpu}" == "ats")
    invalid |= ("${provider}" == "psm2" && "${gpu}" != "nogpu")
    invalid |= ("${thread}" != "runtime" && "${gpu}" != "nogpu")

    // PMIx filters
    invalid |= ("${pmix}" == "pmix" && "${provider}" != "sockets")

    // AM filters
    invalid |= ("${am}" == "am" && "${gpu}" != "nogpu")

    if (invalid) {
        invalid_configs.add("""
${netmod}:${provider}/${compiler}/${am}/${direct}/${config}/${gpu}/${test}/${thread}/${vci}/${async}/${pmix}""")
    }

    return invalid
}

/* Grab the configuration options from the github comment */
@NonCPS
def match_github_phrase() {
    /* Match on the main trigger and any additional configure options */
    def matcher = ("" + env['GITHUB_PR_COMMENT_BODY'] =~ /(test(-main)?:(:?(:?ofi|all),?)+\/(:?(:?sockets|tcp|psm2|verbs|cxi|psm3|all),?)+\/(:?(:?gnu|icc|all),?)+\/(:?(:?am|noam|all),?)+\/(:?(:?netmod|auto|no-odd-even|all),?)+\/(:?(:?debug|default|opt|all),?)+\/(:?(:?nogpu|ats|all),?)+(:?\/(:?gpu|cpu-gpu),?)?(\/(:?(:?runtime|handoff|direct|lockless|all),?)+)?(\/(:?(:?vci1|vci4|all),?)+)?(\/(:?(:?async-single|async-multiple|all),?)+)?(\/(:?(:?pmix|nopmix|all),?)+)?[ =a-zA-Z0-9._-]*)/)
    try {
        jenkins_config_string = "" + matcher.find() ? matcher.group() : "not found"
        if (jenkins_config_string.split(" ").size() > 1) {
            jenkins_config_extras = jenkins_config_string.split(" ", 2)[1].trim()
            jenkins_configs = jenkins_config_string.split(" ")[0].tokenize(':')[1].split("/").collect{it.split(",")}
            jenkins_config_string = jenkins_config_string.split(" ")[0].trim()
            print jenkins_config_string
            print jenkins_config_extras
        } else {
            jenkins_config_string = jenkins_config_string.trim()
            jenkins_configs = jenkins_config_string.tokenize(':')[1].split("/").collect{it.split(",")}
            print jenkins_config_string
        }
    } catch (Exception err) {
        print err.toString()
        currentBuild.result = "FAILURE"
        continue_pipeline = false
        return
    }

    /* Match on any additional environment options */
    def env_matcher = ("" + env['GITHUB_PR_COMMENT_BODY'] =~ /(env:[ =a-zA-Z0-9._-]+)/)
    try {
        jenkins_env_string = "" + env_matcher.find() ? env_matcher.group() : "not found"
        if (!jenkins_env_string.equals("not found")) {
            jenkins_env_string = jenkins_env_string.trim()
            jenkins_envs = String.join("\n", jenkins_env_string.tokenize(':')[1].trim().split(" ").collect{"export " + it})
            print jenkins_envs
        }
    } catch (Exception err) {
        /* It's okay to fail the matcher here, since these are additional options. Just continue as normal */
        jenkins_envs = ""
        print err.toString()
    }

    /* Match on any node requests */
    def node_matcher = ("" + env['GITHUB_PR_COMMENT_BODY'] =~ /(node:[ a-zA-Z0-9._-]+)/)
    try {
        jenkins_node_string = "" + node_matcher.find() ? node_matcher.group() : "not found"
        if (!jenkins_node_string.equals("not found")) {
            jenkins_node = jenkins_node_string.split(" ")[1].trim()
            print jenkins_node
        }
    } catch (Exception err) {
        /* It's okay to fail the matcher here, since these are additional options. Just continue as normal */
        jenkins_node = ""
        print err.toString()
    }
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

/* Parse the github comment */
match_github_phrase()
status_line = "($jenkins_config_string)"
if ("{$jenkins_config_extras}" != "") {
    status_line = "$status_line $jenkins_config_extras"
}
if ("${jenkins_node}" != "") {
    status_line = "$jenkins_node $status_line"
}
status_context = "per-commit: $status_line"

/* Check if the link should be for per-commit-mpich or per-commit-github-main */
if (env['GITHUB_PR_TARGET_BRANCH'].equals("main")) {
    BLUEOCEAN_URL = "https://ancoral001.an.intel.com/blue/organizations/jenkins/per-commit-github-main/detail/per-commit-github-main"
}
print BLUEOCEAN_URL

/* Get the nodes from the "tester_pool" label */
def tester_pool_nodes = "" + get_nodes("tester_pool").join(" || ")
def cassini_nodes = "" + get_nodes("cassini").join(" || ")

def branches = [:]

/* Required groups setup */
def netmods   = jenkins_configs[0]
def providers = jenkins_configs[1]
def compilers = jenkins_configs[2]
def ams       = jenkins_configs[3]
def directs   = jenkins_configs[4]
def configs   = jenkins_configs[5]
def gpus      = jenkins_configs[6]
def tests     = []
def threads   = []
def vcis      = []
def asyncs    = []
def pmixs     = []

/* Optional groups setup */
def optionals = []
if (jenkins_configs.size() == num_groups) {
    /* All optional groups were provided, so grab them from the config */
    for (i = 0; i < num_optional_groups; ++i) {
        optionals[i] = jenkins_configs[num_required_groups + i]
    }
} else {
    /* Some (or all) optional groups were not provided, so figure out which ones were */
    def current_index = num_required_groups

    /* Set defaults first */
    for (i = 0; i < num_optional_groups; ++i) {
        optionals[i] = [ all_defaults[i] ]
    }

    /* Iterate through provided optional groups and figure out the requested values */
    for (i = 0; i < num_optional_groups; ++i) {
        if (jenkins_configs.size() <= current_index) {
            /* If there are no more groups in the input, the rest are default (set above) */
            break
        } else if (jenkins_configs[current_index][0] == "all") {
            /* If the input is "all", assume its for the next group */
            optionals[i] = all_optionals[i]
            current_index = current_index + 1
        } else if (jenkins_configs[current_index][0] in all_optionals[i]) {
            /* Otherwise check if the input matches an option in the current group */
            optionals[i] = jenkins_configs[current_index]
            current_index = current_index + 1
        } /* Else keep the default for this group */
    }
}

if (netmods[0] == "all") netmods = all_netmods
if (providers[0] == "all") providers = all_providers
if (compilers[0] == "all") compilers = all_compilers
if (ams[0] == "all") ams = all_ams
if (directs[0] == "all") directs = all_directs
if (configs[0] == "all") configs = all_configs
if (gpus[0] == "all") gpus = all_gpus
tests   = optionals[0]
threads = optionals[1]
vcis    = optionals[2]
asyncs  = optionals[3]
pmixs   = optionals[4]


for (a in netmods) {
    for (b in providers) {
        for (c in compilers) {
            for (d in ams) {
                for (e in directs) {
                    for (f in configs) {
                        for (g in gpus) {
                            for (h in tests) {
                                for (i in threads) {
                                    for (j in vcis) {
                                        for (k in asyncs) {
                                            for (l in pmixs) {
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

                                                /* Define the stage for each given configuration */
                                                branches["${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"] = {
                                                    def config_name = "${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"
                                                    def node_name = tester_pool_nodes
                                                    def username = "sys_csr1"
                                                    def build_mode = "per-commit"

                                                    /* Set the current node and username depending on the configuration */
                                                    if ("${provider}" == "verbs" || "${provider}" == "psm3") {
                                                        node_name = "anccskl6"
                                                    } else if ("${provider}" == "cxi") {
                                                        node_name = cassini_nodes
                                                    }
                                                    if ("${gpu}" == "ats") {
                                                        node_name = "jfcst-xe"
                                                        build_mode = "per-commit-gpu"
                                                    }
                                                    if ("${jenkins_node}" != "") {
                                                        node_name = "${jenkins_node}"
                                                    }
                                                    /* Throw an exception if the compute resources are offline */
                                                    if (node_name == tester_pool_nodes) {
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
                                                    } else if (node_name == cassini_nodes) {
                                                        def offline_count = 0
                                                        for (node in get_nodes("cassini")) {
                                                            if (check_node_offline(node)) {
                                                                offline_count = offline_count + 1
                                                            }
                                                        }
                                                        if (offline_count == get_nodes("cassini").size()) {
                                                            def errstr = "all nodes in label 'cassini' are offline"
                                                            print errstr
                                                            throw new Exception(errstr);
                                                        }
                                                    } else {
                                                        if (check_node_offline(node_name)) {
                                                            def errstr = "node '${node_name}' is offline"
                                                            print errstr
                                                            throw new Exception(errstr);
                                                        }
                                                    }
                                                    node("${node_name}") {
                                                        cleanWs()
                                                        sh "mkdir -p ${config_name}"
                                                        unstash name: 'per-commit-tarball'
                                                        sh(script: """
#!/bin/bash -x

prefix=""

# Print out the hostname for debugging logs
hostname

cat > per-commit-test-job.sh << "EOF"
#!/bin/bash -x

# Set overlap as default
export SLURM_OVERLAP=1

if [ "${provider}" != "cxi" ]; then
    prefix="srun -N 1"
else
    prefix=""
fi
\${prefix} hostname

if [ "${provider}" != "cxi" ]; then
    prefix="srun"
else
    prefix=""
fi
set +e
\${prefix} rm -rf /tmp/
\${prefix} rm -rf /dev/shm/
set -e

PRE="/state/partition1/home/${username}/"
REL_WORKSPACE="\${WORKSPACE#\$PRE}"
if [ "${provider}" = "cxi" ]; then
    OFI_DIR="/opt/cray/libfabric/1.13.0.0/"
else
    OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"
fi
REMOTE_WS=\$(\${prefix} mktemp -d /tmp/jenkins.tmp.XXXXXXXX)
JENKINS_DIR="\$REMOTE_WS/maint/jenkins"
BUILD_SCRIPT_DIR="\$JENKINS_DIR/scripts"

if [ "${provider}" != "cxi" ]; then
    prefix="sbcast"
else
    prefix="mv"
fi
\${prefix} ${tarball_name} "\${REMOTE_WS}/${tarball_name}"
if [ "${provider}" != "cxi" ]; then
    srun --chdir="\$REMOTE_WS" tar -xf ${tarball_name}
else
    cd \$REMOTE_WS
    tar -xf ${tarball_name}
    cd -
fi

CONFIG_EXTRA="${jenkins_config_extras}"
embedded_ofi="no"
xpmem="yes"
gpudirect="yes"
n_jobs=32
ze_native=""
neo_dir=""
ze_dir=""
xpmem_dir="/usr/local"
fast=""
use_icx="yes"

disable_psm2="no"

thread_cs="per-vci"
mt_model="runtime"

if [ "${config}" = "debug" ]; then
    fast="none"
else
    fast="O3"
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


# Temporarily limit vcis to 2 for psm2, to avoid failures of tests with large number of ranks
if [ "${provider}" = "psm2" -a "${vci}" == "vci4" ]; then
   override_nvcis=2
   export MPIR_CVAR_CH4_NUM_VCIS=\${override_nvcis}
   export MPIR_CVAR_CH4_OFI_MAX_RMA_SEP_CTX=\${override_nvcis}
   export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=\${override_nvcis}
   export MPIR_CVAR_ASYNC_PROGRESS=0
fi

if [ "${thread}" = "handoff" ]; then
    export MPIR_CVAR_ASYNC_PROGRESS=1
fi

echo "Appending mt_xfail_common.conf"
if [ "${provider}" != "cxi" ]; then
    prefix="srun --chdir=\$REMOTE_WS"
else
    prefix=""
fi
\${prefix} /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
\${prefix} /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_common.conf >> \$JENKINS_DIR/xfail.conf"

if [ "${vci}" = "vci4" ]; then
    echo "Appending mt_xfail_vci4.conf"
    \${prefix} /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
    \${prefix} /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_vci4.conf >> \$JENKINS_DIR/xfail.conf"
fi

echo "Appending mt_xfail_\${runtime_mt_model}.conf"
\${prefix} /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
\${prefix} /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_\${runtime_mt_model}.conf >> \$JENKINS_DIR/xfail.conf"

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
    if [ "${provider}" == "psm3" ]; then
        OFI_DIR="/home/sys_csr1/software/libfabric/psm3-dynamic"
    else
        embedded_ofi="yes"
    fi
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

# Temporary constraint until g++ and gfortran are installed
if [ "${provider}" = "cxi" ]; then
    CONFIG_EXTRA="\$CONFIG_EXTRA --disable-cxx --disable-fortran"
fi

# AM builds force direct mode with global locking
if [ "${am}" = "am" ]; then
    thread_cs="global"
    mt_model="direct"
fi

# Force configurations if merging with main due to some incompatibilities
if [ "\${GITHUB_PR_TARGET_BRANCH}" == "main" ]; then
    gpudirect="no"
fi

if [ "\${provider}" = "cxi" -a "\${compiler}" = "icc" ]; then
    use_icx="yes"
fi

NAME="${config_name}"

${jenkins_envs}

export LD_LIBRARY_PATH=\$OFI_DIR/lib/:\$LD_LIBRARY_PATH

\${prefix} /bin/bash \${BUILD_SCRIPT_DIR}/test-worker.sh \
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
    -I \$use_icx \
    -j "\$CONFIG_EXTRA"

EOF

chmod +x per-commit-test-job.sh
if [ "${provider}" != "cxi" ]; then
    prefix="salloc -J per-commit:${provider}:${compiler}:${am}:${direct}:${config}:${gpu}:${test}:${thread}:${vci}:${async}:${pmix} -N 1 -t 360"
    if [ "${provider}" == "psm3" -a "${gpu}" == "ats" ]; then
      #Exclude using ats4 on jfcst since ats4 does not discover IB nics
      prefix="\${prefix} -x ats4"
    fi
else
    prefix=""
fi
\${prefix} ./per-commit-test-job.sh

""")
                                                        archiveArtifacts "$config_name/**"
                                                        junit "${config_name}/test/mpi/summary.junit.xml"
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
    /* Comment invalid branches before running tests */
    comment_invalid_configs()

    if (branches.isEmpty()) {
        continue_pipeline = false
        currentBuild.result = "FAILURE"
        status_message = "No Valid Configurations"
    } else if (continue_pipeline) {
        try {
            /* Checkout the repository */
            stage('Checkout') {
                setBuildStatus("In Progress", "PENDING", status_context, env['GITHUB_PR_HEAD_SHA'], BLUEOCEAN_URL)
                cleanWs()

                // Get some code from a GitHub repository
                checkout([$class: 'GitSCM',
                          branches: [[name: 'origin-pull/pull/${GITHUB_PR_NUMBER}/head']],
                          doGenerateSubmoduleConfigurations: false,
                          extensions: [
                              [$class: 'SubmoduleOption',
                                  disableSubmodules: false,
                                  recursiveSubmodules: true
                              ]],
                          submoduleCfg: [],
                          userRemoteConfigs: [[
                              credentialsId: 'password-sys_csr1_github',
                              refspec: '+refs/pull/${GITHUB_PR_NUMBER}/merge:refs/remotes/origin-pull/pull/${GITHUB_PR_NUMBER}/head',
                              url: 'https://github.com/intel-innersource/libraries.runtimes.hpc.mpi.mpich-aurora.git'
                          ]]
                         ])
                    sh(script: """
git submodule sync
git submodule update --init --recursive

# If this branch is being merged with main, grab the jenkins scripts from integration
if [ ! -d maint/jenkins ]; then
    git checkout origin/integration -- maint/jenkins
fi
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
                stash includes: 'mpich-per-commit-*.tar.bz2', name: 'per-commit-tarball'
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

/* Publish the results */
node (tester_pool_nodes) {
    stage ('Publish') {
        if (currentBuild.result == "ABORTED") {
            setBuildStatus("Aborted", currentBuild.result, status_context, env['GITHUB_PR_HEAD_SHA'], BLUEOCEAN_URL)
        } else {
            setBuildStatus(status_message, currentBuild.result, status_context, env['GITHUB_PR_HEAD_SHA'], BLUEOCEAN_URL)
        }
    }
}
