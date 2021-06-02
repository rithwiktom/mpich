import java.util.regex.*
import com.cloudbees.groovy.cps.NonCPS
import org.jenkinsci.plugins.workflow.steps.*

def tarball_name='mpich-drops.tar.bz2'

node('anfedclx8') {
    try {
        stage('Checkout') {
            cleanWs()

            // Get some code from a GitHub repository
            checkout([$class: 'GitSCM',
                      branches: [[name: '*/drops']],
                      doGenerateSubmoduleConfigurations: false,
                      extensions: [[$class: 'SubmoduleOption',
                                    disableSubmodules: false,
                                    recursiveSubmodules: true]],
                      submoduleCfg: [],
                      userRemoteConfigs: [[credentialsId: 'password-sys_csr1_github',
                                           url: 'https://github.com/intel-innersource/libraries.runtimes.hpc.mpi.mpich-aurora.git' ]]
                     ])
                    sh(script: """
git submodule sync
git submodule update --init --recursive
""")
        }
        stage('Autogen') {
            sh label: '', script: """
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

tar --exclude=${tarball_name} -cjf ${tarball_name} *
cp maint/jenkins/mpich-ofi.spec .
cp maint/jenkins/drop_version .
cp maint/jenkins/release_version .
# The following are useful in the setup rpm-build stage
cp maint/jenkins/drop_version \$HOME/rpmbuild/drop_version
cp maint/jenkins/release_version \$HOME/rpmbuild/release_version
cp maint/jenkins/mpich-ofi.spec \$HOME/rpmbuild/SPECS/mpich-ofi.spec
"""
            stash includes: 'mpich-drops.tar.bz2,mpich-ofi.spec,drop_version,release_version', name: 'drop-tarball'
            cleanWs()
        }
    } catch (Exception err) {
        exit
    }
}

def branches = [:]

def providers = ['sockets', 'psm2', 'cxi']
def compilers = ['gnu', 'icc']
def configs = ['debug', 'default']
def pmixs = ['pmix', 'nopmix']
def flavors = ['regular', 'gen9', 'dg1', 'ats', 'nogpu']

def run_tests = "no"

for (a in providers) {
    for (b in compilers) {
        for (c in configs) {
            for (d in pmixs) {
                for (e in flavors) {
                    def provider = a
                    def compiler = b
                    def config = c
                    def pmix = d
                    def flavor = e
                    if ("${provider}" == "verbs" && "${flavor}" == "gen9") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${provider}" != "sockets") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${flavor}" == "gen9") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${provider}" == "cxi" && "${flavor}" != "regular") {
                        continue;
                    }
                    if ("${provider}" == "cxi" && "${pmix}" == "pmix") {
                        continue;
                    }
                    // This build is for anccskl6, so oneCCL can be tested with the drop
                    // skl6 does not get latest oneAPI compiler builds so only creating gnu builds
                    if ("${flavor}" == "nogpu" && "${provider}" == "psm2") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${provider}" == "cxi") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${compiler}" == "icc") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${pmix}" == "pmix") {
                        continue;
                    }
                    branches["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                        node('anfedclx8') {
                            def config_name = "${provider}-${compiler}-${config}-${pmix}-${flavor}"
                            sh "mkdir -p ${config_name}"
                            unstash name: 'drop-tarball'

                            sh(script: """
#!/bin/bash -x

cat > drop-test-job.sh << "EOF"
#!/bin/bash -x

srun -N 1 hostname

set +e
srun --chdir="/tmp" rm -rf /tmp/
srun --chdir="/dev/shm" rm -rf /dev/shm/
set -e

VERSION=drop\$(<drop_version)
RELEASE=\$(<release_version)
CUSTOM_VERSION_STRING="\${VERSION}_release\${RELEASE}"
PRE="/state/partition1/home/sys_csr1/"
REL_WORKSPACE="\${WORKSPACE#\$PRE}"
if [ "${provider}" == "cxi" ]; then
    OFI_DIR="/opt/intel/csr/ofi/sockets-dynamic"
else
    OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"
fi
REMOTE_WS=\$(srun --chdir=/tmp mktemp -d /tmp/jenkins.tmp.XXXXXXXX)
JENKINS_DIR="\$REMOTE_WS/maint/jenkins"
BUILD_SCRIPT_DIR="\$JENKINS_DIR/scripts"

embedded_ofi="no"
daos="yes"
xpmem="yes"
n_jobs=128
neo_dir=""
ze_dir=""
ze_native=""
config_extra=""

pmix_string=""
if [ "${pmix}" == "pmix" ]; then
    pmix_string="-pmix"
    export LD_LIBRARY_PATH=/opt/openpmix/lib:\$LD_LIBRARY_PATH
fi
flavor_string=""
if [ "${flavor}" != "regular" ]; then
    flavor_string="-${flavor}"
fi

# These directories will probably need to be updated going forward
neo_dir=/opt/neo/release/2020.10.05

#Set ze path for all the builds
ze_dir=/opt/neo/release/2020.10.05
# Build with native support for GPU-specific RPMs
if [ "${flavor}" == "dg1" -o "${flavor}" == "ats" ]; then
    ze_native="${flavor}"
fi

if [ "${flavor}" == "nogpu" ]; then
    # empty ze since it is not needed on skl6
    ze_dir=""
    embedded_ofi="yes"
    # PSM3 provider is used for testing oneCCL over Mellanox
    # so that we can use multiple NICs on skl6. This version
    # of rpm is used by oneCCL CI testing.
    config_extra+=" --enable-psm3"
    daos="no"
    xpmem="no"
fi

NAME="mpich-ofi-${provider}-${compiler}-${config}\${pmix_string}\${flavor_string}-\$VERSION"

if [ "${flavor}" == "gen9" -o "${flavor}" == "dg1" -o "${flavor}" == "ats" ]; then
    embedded_ofi="yes"
    # PSM3 provider is used for testing oneCCL over Mellanox
    # so that we can use multiple NICs. This is needed for
    # JLSE builds where we provide embedded libfabric
    config_extra+=" --enable-psm3"
    daos="no"
    xpmem="no"
fi

if [ "${flavor}" == "dg1" -o "${flavor}" == "gen9" ]; then
    config_extra+=" --disable-ze-double"
fi

if [ "${provider}" != "sockets" ]; then
    daos="no"
fi

INSTALL_DIR="/tmp/\${NAME}/usr/mpi/\${NAME}/"

# set json files paths
export MPIR_CVAR_COLL_CH4_SELECTION_TUNING_JSON_FILE="\${JENKINS_DIR}/json-files/CH4_coll_tuning.json"
export MPIR_CVAR_COLL_SELECTION_TUNING_JSON_FILE="\${JENKINS_DIR}/json-files/MPIR_Coll_tuning.json"
export MPIR_CVAR_COLL_POSIX_SELECTION_TUNING_JSON_FILE="\${JENKINS_DIR}/json-files/POSIX_coll_tuning.json"

sbcast ${tarball_name} "\${REMOTE_WS}/${tarball_name}"
srun --chdir="\$REMOTE_WS" tar -xf ${tarball_name}

srun --chdir="\$BUILD_SCRIPT_DIR" "\$BUILD_SCRIPT_DIR/generate_drop_files.sh" "\$REMOTE_WS" \
    "\$JENKINS_DIR" "${provider}" "${compiler}" "${config}" "${pmix}" "${flavor}"

provider_string="${provider}"
if [ "${provider}" == "verbs" ]; then
    provider_string="verbs;ofi_rxm"
fi

build_dg1="no"
if [ "${flavor}" == "dg1" ]; then
    build_dg1="yes"
fi

srun --chdir="\$REMOTE_WS" /bin/bash \${BUILD_SCRIPT_DIR}/test-worker.sh \
    -B \${build_dg1} \
    -h \${REMOTE_WS}/_build \
    -i \${OFI_DIR} \
    -c ${compiler} \
    -o ${config} \
    -d noam \
    -b drop \
    -s auto \
    -p "\${provider_string}" \
    -m \${n_jobs} \
    -N "\${neo_dir}" \
    -r \$REL_WORKSPACE/${config_name} \
    -t 2.0 \
    -x ${run_tests} \
    -k \$embedded_ofi \
    -Y "\${ze_native}" \
    -Z "\${ze_dir}" \
    -j "--with-default-ofi-provider=\${provider_string} --disable-opencl \${config_extra}" \
    -D \$daos \
    -E \$xpmem \
    -P ${pmix} \
    -y \$CUSTOM_VERSION_STRING \
    -f \$INSTALL_DIR

if [ "${run_tests}" = "yes" ]; then
    srun cp test/mpi/summary.junit.xml ${config_name}/test/mpi/summary.junit.xml
fi

srun mkdir -p \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 'COPYRIGHT' \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 'CHANGES' \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 README \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 README.envvar \$INSTALL_DIR/share/doc/mpich
srun mkdir -p /tmp/\${NAME}/usr/mpi/modulefiles/
srun cp -r \${REMOTE_WS}/modulefiles/mpich/ /tmp/\${NAME}/usr/mpi/modulefiles/
srun cp -r \${JENKINS_DIR}/json-files \$INSTALL_DIR
srun cp -r \${REMOTE_WS}/mpich.sh \$INSTALL_DIR
srun --chdir="/tmp" tar cjf \$NAME.tar.bz2 \$NAME
srun --chdir="/tmp" rm -rf \$INSTALL_DIR
srun --chdir="/tmp" mkdir -p /home/sys_csr1/rpmbuild/{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
srun --chdir="/tmp" mv \$NAME.tar.bz2 /home/sys_csr1/rpmbuild/SOURCES/\$NAME.tar.bz2
srun --chdir="\$WORKSPACE" mkdir -p maint/jenkins
srun --chdir="\$REMOTE_WS" cp \$JENKINS_DIR/drop_version \$WORKSPACE/maint/jenkins/drop_version

EOF

chmod +x drop-test-job.sh
salloc -J drop:${provider}:${compiler}:${config}:${pmix} -N 1 -t 360 ./drop-test-job.sh

""")
                            archiveArtifacts "$config_name/**"
                            if ("${run_tests}" == "yes") {
                                junit "${config_name}/test/mpi/summary.junit.xml"
                            }
                            cleanWs()
                        }
                    }
                }
            }
        }
    }
}

stage('Build') {
    parallel branches
}

stage('Setup RPM Build') {
    node('anfedclx8') {
        unstash name: "$stash_name"
        sh(script: """
#!/bin/bash -xe

cd \$HOME/rpmbuild

""")
    }
}

def rpms = [:]

for (a in providers) {
    for (b in compilers) {
        for (c in configs) {
            for (d in pmixs) {
                for (e in flavors) {
                    def provider = a
                    def compiler = b
                    def config = c
                    def pmix = d
                    def flavor = e
                    if ("${provider}" == "verbs" && "${flavor}" == "gen9") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${provider}" != "sockets") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${flavor}" == "gen9") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${provider}" == "cxi" && "${flavor}" != "regular") {
                        continue;
                    }
                    if ("${provider}" == "cxi" && "${pmix}" == "pmix") {
                        continue;
                    }
                    // This build is for anccskl6, so oneCCL can be tested with the drop
                    if ("${flavor}" == "nogpu" && "${provider}" == "psm2") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${provider}" == "cxi") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${compiler}" == "icc") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${pmix}" == "pmix") {
                        continue;
                    }
                    rpms["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                        node('anfedclx8') {
                            def version = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/drop_version')
                            def release = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/release_version')
                            sh(script: """
#!/bin/bash -xe

pushd \$HOME/rpmbuild

version=\$(<drop_version)
release=\$(<release_version)

pmix_string=""
if [ "${pmix}" == "pmix" ]; then
    pmix_string="-pmix"
fi
flavor_string=""
if [ "${flavor}" != "regular" ]; then
    flavor_string="-${flavor}"
fi

NAME="mpich-ofi-${provider}-${compiler}-${config}\${pmix_string}\${flavor_string}-drop\$version"

pwd
srun rpmbuild -bb \
    --define="_name \$NAME" \
    --define="_version \$version" \
    --define="_release \$release" \
    --define="_provider ${provider}" \
    --define="_configs ${config}" \
    --define="_compiler ${compiler}" \
    --define="_flavor ${flavor}" \
    SPECS/mpich-ofi.spec

rm -rf BUILD/\${NAME}

RPM_NAME="\$NAME-\$version-\$release.x86_64.rpm"

popd

cp \$HOME/rpmbuild/RPMS/x86_64/\$RPM_NAME .
""")
                            def rpm_name = "mpich-ofi-${provider}-${compiler}-${config}"
                            if ("$pmix" == "pmix") {
                                rpm_name = rpm_name + "-pmix"
                            }
                            if ("$flavor" != "regular") {
                                rpm_name = rpm_name + "-${flavor}"
                            }
                            def stash_name = "$rpm_name"
                            rpm_name = rpm_name + "-drop${version}-${version}-${release}.x86_64.rpm"
                            stash includes: "*.rpm", name: "$stash_name"
                            cleanWs()
                        }
                    }
                }
            }
        }
    }
}

stage('Build RPMs') {
    parallel rpms
}

def rpm_tests = [:]

for (a in providers) {
    for (b in compilers) {
        for (c in configs) {
            for (d in pmixs) {
                for (e in flavors) {
                    def provider = a
                    def compiler = b
                    def config = c
                    def pmix = d
                    def flavor = e
                    def testgpu = 0
                    /* The gen9 machine only uses sockets */
                    if (("${provider}" == "psm2" || "${provider}" == "verbs") && "${flavor}" == "gen9") {
                        continue
                    }
                    /* The only current PMIx setup is using sockets and will not be installed on gen9 */
                    if ("${pmix}" == "pmix" && ("${provider}" != "sockets" || "${flavor}" == "gen9")) {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${provider}" == "psm2") {
                        continue
                    }
                    /* We don't have a way to automate testing with cxi yet */
                    if ("${provider}" == "cxi") {
                        continue
                    }
                    // This build is for anccskl6, so oneCCL can be tested with the drop
                    if ("${flavor}" == "nogpu" && "${provider}" == "psm2") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${provider}" == "cxi") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${compiler}" == "icc") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${pmix}" == "pmix") {
                        continue;
                    }
                    /* We currently have no way to install an RPM on a verbs cluster */
                    rpm_tests["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                        def node_name = "anfedclx8-admin"
                        if ("${provider}" == "verbs") {
                            node_name = "anccskl6"
                        }
                        if ("${flavor}" == "dg1") {
                            node_name = "a20-testbed"
                            testgpu = 1
                        }
                        if ("${flavor}" == "ats") {
                            node_name = "jfcst-xe"
                            testgpu = 1
                        }
                        node("${node_name}") {
                            cleanWs()
                            def stash_name = "mpich-ofi-${provider}-${compiler}-${config}"
                            if ("$pmix" == "pmix") {
                                stash_name = stash_name + "-pmix"
                            }
                            if ("$flavor" != "regular") {
                                stash_name = stash_name + "-${flavor}"
                            }
                            unstash name: 'drop-tarball'
                            unstash name: "$stash_name"
                            sh(script: """
#!/bin/bash -x

export version=\$(<drop_version)
export release=\$(<release_version)
export job="drop\${version}"
export nodes=1
export TARBALL="mpich-drops.tar.bz2"

cat > RPM-testing-drop-job.sh << "EOF"
#!/bin/bash -x

srun --chdir="\$WORKSPACE" /bin/bash \${WORKSPACE}/maint/jenkins/scripts/rpm-testing.sh \
    \${job} \${nodes} \${version} \${release} ${provider} ${compiler} ${config} ${pmix} ${flavor} ${testgpu} \$WORKSPACE

EOF

chmod +x RPM-testing-drop-job.sh
tar -xf \$TARBALL

salloc -J "\$job-${provider}-${compiler}-${config}-${pmix}-${flavor}" -N \${nodes} -t 600 ./RPM-testing-drop-job.sh
""")
                            junit "**/summary.junit.xml"
                        }
                    }
                }
            }
        }
    }
}

stage('Test RPMs') {
    parallel rpm_tests
}

// Tag update and RPM upload stems are broken at the moment. They should be done manually until fixed.
return

stage('Update Drop Tag') {
    node('anfedclx8') {
        // Get some code from a GitHub repository
        checkout([$class: 'GitSCM',
                 branches: [[name: '*/drops']],
                 doGenerateSubmoduleConfigurations: false,
                 extensions: [[$class: 'SubmoduleOption',
                 disableSubmodules: false,
                 recursiveSubmodules: true]],
                 submoduleCfg: [],
                 userRemoteConfigs: [[credentialsId: 'password-sys_csr1_github',
                                      url: 'https://github.com/intel-innersource/libraries.runtimes.hpc.mpi.mpich-aurora.git' ]]
        ])
        sh(script: """
#!/bin/bash -xe

version=\$(<maint/jenkins/drop_version)
release=\$(<maint/jenkins/release_version)

tag_string="drop\${version}"
if [ "\${release}" != "0" ]; then
    tag_string="\${tag_string}.\${release}"
fi

# Turn off errors because the tag may not exist yet
set +e
git tag -d \${tag_string}
git push origin :refs/tags/\${tag_string}
set -e

git tag \${tag_string}
git push --tags origin

""")
        cleanWs()
    }
}

def rpms_upload = [:]

for (a in providers) {
    for (b in compilers) {
        for (c in configs) {
            for (d in pmixs) {
                for (e in flavors) {
                    def provider = a
                    def compiler = b
                    def config = c
                    def pmix = d
                    def flavor = e
                    if ("${provider}" == "verbs" && "${flavor}" == "gen9") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${provider}" != "sockets") {
                        continue;
                    }
                    if ("${pmix}" == "pmix" && "${flavor}" == "gen9") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "dg1" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${pmix}" == "pmix") {
                        continue
                    }
                    if ("${flavor}" == "ats" && "${provider}" == "psm2") {
                        continue
                    }
                    if ("${provider}" == "cxi" && "${flavor}" != "regular") {
                        continue;
                    }
                    if ("${provider}" == "cxi" && "${pmix}" == "pmix") {
                        continue;
                    }
                    // This build is for anccskl6, so oneCCL can be tested with the drop
                    if ("${flavor}" == "nogpu" && "${provider}" == "psm2") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${provider}" == "cxi") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${compiler}" == "icc") {
                        continue;
                    }
                    if ("${flavor}" == "nogpu" && "${pmix}" == "pmix") {
                        continue;
                    }
                    rpms_upload["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                        node('anfedclx8') {
                            def version = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/drop_version')
                            def release = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/release_version')
                            withCredentials([string(credentialsId: 'artifactory_api_key', variable: 'API_KEY')]) {
                                sh(script: """
#!/bin/bash

version=\$(<drop_version)
release=\$(<release_version)

pmix_string=""
dir="drop"$version"."$release
subdir=""

if [ "${pmix}" == "pmix" ]; then
    pmix_string="-pmix"
    subdir="pmix"
fi
flavor_string=""
if [ "${flavor}" != "regular" ]; then
    flavor_string="-${flavor}"
    subdir="${flavor}"
fi
if [ "${flavor}" == "regular" ]; then
    subdir="regular"
fi

NAME="mpich-ofi-${provider}-${compiler}-${config}\${pmix_string}\${flavor_string}-drop\$version"
RPM_NAME="\$NAME-\$version-\$release.x86_64.rpm"

curl -H 'X-JFrog-Art-Api:$API_KEY' -XPUT https://af02p-or.devtools.intel.com/artifactory/mpich-aurora-or-local/\$dir/\$subdir -T \$HOME/rpmbuild/RPMS/x86_64/\$RPM_NAME 

""")
                            }
                        }
                    }
                }
            }
        }
    }
}

stage('Upload RPMs') {
    parallel rpms_upload
}
