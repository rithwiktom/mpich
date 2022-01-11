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
def continue_pipeline = true
BLUEOCEAN_URL = "https://ancoral001.an.intel.com/view/all/job/per-commit-warnings/"
def status_context = "per-commit-warnings"
def status_message = "Completed"
currentBuild.result = "SUCCESS"

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

/* Required groups setup */
def netmods   = [ "ofi" ]
def providers = [ "sockets" ]
def compilers = [ "gnu" ]
def ams       = [ "noam" ]
def directs   = [ "auto" ]
def configs   = [ "debug", "default" ]
def gpus      = [ "nogpu" ]
def tests     = [ "cpu-gpu" ]
def threads   = [ "runtime" ]
def vcis      = [ "vci1" ]
def asyncs    = [ "async-single" ]
def pmixs     = [ "nopmix" ]

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

                                                /* Define the stage for each given configuration */
                                                branches["${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"] = {
                                                    def config_name = "${netmod}-${provider}-${compiler}-${am}-${direct}-${config}-${gpu}-${test}-${thread}-${vci}-${async}-${pmix}"
                                                    def node_name = tester_pool_nodes
                                                    def username = "sys_csr1"
                                                    def build_mode = "per-commit"

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
                                                        unstash name: 'per-commit-tarball'
                                                        sh(script: """
#!/bin/bash -x

# Print out the hostname for debugging logs
hostname

cat > per-commit-warnings-job.sh << "EOF"
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
json="yes"
n_jobs=72
ze_native=""
neo_dir=""
ze_dir=""
xpmem_dir="/usr/local"

disable_psm2="no"

thread_cs="per-vci"
mt_model="runtime"

fast="none"

# Set common multi-threading environment (if enabled)
if [ "${thread}" != "runtime" ]; then
    mt_model="${thread}"
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

    echo "Appending mt_xfail_\${mt_model}.conf"
    srun --chdir="\$REMOTE_WS" /bin/bash -c "echo '' >> \$JENKINS_DIR/xfail.conf"
    srun --chdir="\$REMOTE_WS" /bin/bash -c "cat \$JENKINS_DIR/mt_xfail_\${mt_model}.conf >> \$JENKINS_DIR/xfail.conf"

    if [ "${config}" = "debug" ]; then
        export MPIR_CVAR_CH4_MT_MODEL=\$mt_model
        mt_model="runtime"
    fi

    if [ "${async}" = "async-single" ]; then
        export MPIR_CVAR_CH4_MAX_PROGRESS_THREADS=1
    fi

    if [ "${provider}" = "psm2" ]; then
        export FI_PSM2_LOCK_LEVEL=1
    fi

    CONFIG_EXTRA="\$CONFIG_EXTRA --disable-spawn --with-ch4-max-vcis=\${nvcis}"
fi

# Set the environment for GPU systems
if [ "$gpu" = "ats" ]; then
    # TODO: enable when IPC support is enabled
    gpudirect=no
    embedded_ofi="yes"
    xpmem="no"
    neo_dir=/usr
    ze_dir=/usr
    ze_native="$gpu"
    disable_psm2="yes"
elif [ "$gpu" = "nogpu" ]; then
    CONFIG_EXTRA="\$CONFIG_EXTRA --without-ze"
fi

# AM builds force direct mode with global locking
if [ "${am}" = "am" ]; then
    thread_cs="global"
    mt_model="direct"
fi

# Force configurations if merging with main due to some incompatibilities
if [ "\${GITHUB_PR_TARGET_BRANCH}" == "main" -o "\${GITHUB_PR_TARGET_BRANCH}" == "integration_main" ]; then
    gpudirect="no"
    json="no"
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
    -r \${REL_WORKSPACE}/\${NAME} \
    -t 2.0 \
    -k "\${embedded_ofi}" \
    -J "\${json}" \
    -M "\${mt_model}" \
    -X "\${xpmem_dir}" \
    -H "\${gpudirect}" \
    -Y "\${ze_native}" \
    -Z "\${ze_dir}" \
    -G ${test} \
    -z "-L\$neo_dir/lib64" \
    -E \$xpmem \
    -x "no" \
    -W "yes" \
    -j "\$CONFIG_EXTRA"

if test -z "`cat \${REL_WORKSPACE}/\${NAME}/filtered-make.txt`" ; then
    failures=0
else
    failures=1
fi

echo "<testsuites>" >> summary.junit.xml

echo "    <testsuite" >> summary.junit.xml
echo "        failures=\\"\${failures}\\"" >> summary.junit.xml
echo "        errors=\\"0\\"" >> summary.junit.xml
echo "        skipped=\\"0\\"" >> summary.junit.xml
echo "        tests=\\"1\\"" >> summary.junit.xml
echo "        date=\\"`date +%Y-%m-%d-%H-%M`\\"" >> summary.junit.xml
echo "        name=\\"summary_junit_xml\\" >" >> summary.junit.xml

echo "        <testcase name=\\"compilation\\" time=\\"0\\" >" >> summary.junit.xml

if [ \${failures} != "0" ] ; then
  echo "            <failure><![CDATA[`cat \${REL_WORKSPACE}/\${NAME}/filtered-make.txt`]]></failure>" >> summary.junit.xml
fi

echo "        </testcase>" >> summary.junit.xml
echo "    </testsuite>" >> summary.junit.xml
echo "</testsuites>" >> summary.junit.xml

mv summary.junit.xml \${REL_WORKSPACE}/\${NAME}/summary.junit.xml

EOF

chmod +x per-commit-warnings-job.sh
salloc -J warning:${compiler}:${direct}:${config}:${gpu}:${test}:${thread}:${vci}:${async}:${pmix} -N 1 -t 60 ./per-commit-warnings-job.sh

""")
                                                        archiveArtifacts "${config_name}/**"
                                                        junit "${config_name}/summary.junit.xml"
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
    stage ('Build MPICH') {
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
