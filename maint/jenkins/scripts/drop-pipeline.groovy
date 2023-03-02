import java.util.regex.*
import com.cloudbees.groovy.cps.NonCPS
import org.jenkinsci.plugins.workflow.steps.*

def tarball_name='mpich-drops.tar.bz2'

def Taranis_build(provider, compiler, config, pmix, flavor) {
    check = false
    // Taranis Builds
    check |= ("${provider}" == "psm2" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "psm2" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "psm2" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "psm2" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")

    check |= ("${provider}" == "tcp" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "tcp" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "tcp" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "tcp" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")

    check |= ("${provider}" == "cxi" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "cxi" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "cxi" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "regular" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "cxi" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "regular" && "${pmix}" == "nopmix")

    return check
}

def Sunspot_builds(provider, compiler, config, pmix, flavor) {
    check = false
    // Sunspot Builds (no XPMEM, external libfabric, with GPU, all providers, PMIX is optional)
    check |= ("${provider}" == "all" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "pmix")
    check |= ("${provider}" == "all" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "gpu" && "${pmix}" == "pmix")
    check |= ("${provider}" == "all" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "pmix")
    check |= ("${provider}" == "all" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "gpu" && "${pmix}" == "pmix")
    return check
}

def JLSE_builds(provider, compiler, config, pmix, flavor) {
    check = false

    // JLSE Builds (no XPMEM, external libfabric)
    // Sockets Provider
    check |= ("${provider}" == "sockets" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")
    // NoGPU Builds (GPU disabled, no XPMEM, external libfabric)
    check |= ("${provider}" == "sockets" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "nogpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "icc" && "${config}" == "debug" && "${flavor}" == "nogpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "gnu" && "${config}" == "default" && "${flavor}" == "nogpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "sockets" && "${compiler}" == "gnu" && "${config}" == "debug" && "${flavor}" == "nogpu" && "${pmix}" == "nopmix")

    return check
}

def check_config(provider, compiler, config, pmix, flavor) {
    check = false
    check |= Taranis_build(provider, compiler, config, pmix, flavor)
    check |= Sunspot_builds(provider, compiler, config, pmix, flavor)
    check |= JLSE_builds(provider, compiler, config, pmix, flavor)
    // Also need these build for testing references.
    check |= ("${provider}" == "all" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")
    check |= ("${provider}" == "cxi" && "${compiler}" == "icc" && "${config}" == "default" && "${flavor}" == "gpu" && "${pmix}" == "nopmix")

    return check
}

def branches = [:]

// The "all" provider means that the build supports all providers. This is normal for the debug
// build, but using this provider enables it for a default build as well
def providers = ['all', 'sockets', 'psm2', 'cxi', 'psm3', 'tcp']
def compilers = ['gnu', 'icc']
def configs = ['debug', 'default']
def pmixs = ['pmix', 'nopmix']
def flavors = ['regular', 'gpu', 'nogpu']

def run_tests = "no"

if (params.build_rpms) {
    node('anfedclx8') {
        stage('Cleanup RPM Directory') {
            sh(script: """rm -rf \$HOME/rpmbuild""")
            sh(script: """mkdir -p \$HOME/rpmbuild/SPECS""")
        }
    }

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

cd test/mpi

./autogen.sh --with-autotools=\$AUTOTOOLS_DIR | tee test-a.txt

if [ ! -f ./configure ]; then
    exit 1;
fi

cd -

tar --exclude=${tarball_name} -cjf ${tarball_name} *
cp maint/jenkins/mpich-ofi.spec .
cp maint/jenkins/drop_version .
cp maint/jenkins/release_version .
# The following are useful in the setup rpm-build stage
cp maint/jenkins/drop_version \$HOME/rpmbuild/drop_version
cp maint/jenkins/release_version \$HOME/rpmbuild/release_version
cp maint/jenkins/mpich-ofi.spec \$HOME/rpmbuild/SPECS/mpich-ofi.spec
mkdir -p \$HOME/rpmbuild/SOURCES/${tarball_name}
cp ${tarball_name} \$HOME/rpmbuild/SOURCES/${tarball_name}
"""
                stash includes: 'mpich-drops.tar.bz2,mpich-ofi.spec,drop_version,release_version', name: 'drop-tarball'
                cleanWs()
            }
        } catch (Exception err) {
            exit
        }
    }

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

                        if (check_config(provider, compiler, config, pmix, flavor) == false) {
                            continue
                        }

                        branches["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                            node('anfedclx8') {
                                def config_name = "${provider}-${compiler}-${config}-${pmix}-${flavor}"
                                sh "mkdir -p ${config_name}"
                                unstash name: 'drop-tarball'

                                sh(script: """
#!/bin/bash -x

cat > hydra-pmi-proxy-cleanup.sh << "EOF"
#!/bin/bash -x

set -e
set -x
hostname

INSTALL_DIR=\$1
ls -lhR \$INSTALL_DIR

# Remove unneeded dependencies on hydra_pmi_proxy
hydra_deps=("libze_loader.so" "libimf.so")
hydra_path="\$INSTALL_DIR/bin/hydra_pmi_proxy"

for hydra_dep in "\${hydra_deps[@]}"; do
    dep=\$(ldd \$hydra_path | awk '{ print \$1 }' | sed -n "/\${hydra_dep}/p")
    if [ "x\${dep}" != "x" ]; then
        echo "Removing dependence '\${dep}' from hydra_pmi_proxy"
        patchelf --remove-needed "\${dep}" "\$hydra_path"
    fi
done
EOF

chmod +x hydra-pmi-proxy-cleanup.sh

cat > drop-test-job.sh << "EOF"
#!/bin/bash -x

# Set overlap as default
export SLURM_OVERLAP=1

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
if [ "${provider}" == "cxi" -o "${provider}" == "all" ]; then
    OFI_DIR="/opt/intel/csr/ofi/sockets-dynamic"
else
    OFI_DIR="/opt/intel/csr/ofi/${provider}-dynamic"
fi
REMOTE_WS=\$(srun --chdir=/tmp mktemp -d /tmp/jenkins.tmp.XXXXXXXX)
JENKINS_DIR="\$REMOTE_WS/maint/jenkins"
BUILD_SCRIPT_DIR="\$JENKINS_DIR/scripts"

ofi_domain="yes"
embedded_ofi="no"
daos="yes"
xpmem="yes"
gpudirect="yes"
n_jobs=32
neo_dir=""
ze_dir=""
ze_native=""
config_extra=""
cpu="native"

fast=""
if [ "${config}" = "debug" ]; then
    fast="none"
elif [ "${flavor}" = "nogpu" ]; then
    fast="O3"
else
    fast="avx"
fi

pmix_string=""
if [ "${pmix}" == "pmix" ]; then
    pmix_string="-pmix"
    export LD_LIBRARY_PATH=/opt/pmix-4.2.2/lib:\$LD_LIBRARY_PATH
fi
flavor_string=""
if [ "${flavor}" != "regular" ]; then
    flavor_string="-${flavor}"
fi

neo_dir=/usr

#Set ze path for all the builds
ze_dir=/usr
# Build with native support for GPU-specific RPMs for Power-On
# Table: https://github.com/intel-innersource/drivers.gpu.specification.platforms/blob/generated_cs/gen/templates/doc/listing.md
if [ "${flavor}" == "regular" ]; then
    ze_native="pvc"
fi

NAME="mpich-ofi-${provider}-${compiler}-${config}\${pmix_string}\${flavor_string}-\$VERSION"

if [ "${flavor}" == "nogpu" ]; then
    # empty ze since it is not needed on skl6
    ze_dir=""
    embedded_ofi="no"
    # PSM3 provider is used for testing oneCCL over Mellanox
    # so that we can use multiple NICs on skl6. This version
    # of rpm is used by oneCCL CI testing.
    gpudirect="no"
    config_extra+=" --enable-psm3 --without-ze"
    daos="no"
    xpmem="no"
    # The nogpu builds are meant for JLSE Iris nodes, which don't have avx512 support.
    # We should not use -march=native for these builds
    cpu=""
elif [ "${flavor}" == "gpu" ]; then
    embedded_ofi="no"
    # PSM3 provider is used for testing oneCCL over Mellanox
    # so that we can use multiple NICs. This is needed for
    # JLSE builds where we provide embedded libfabric
    config_extra+=" --enable-psm3"
    # daos = no when provider = psm2 or psm3 or socket
    # daos = yes when provider = cxi or tcp or all
    if [ "${provider}" == "psm2" ] || [ "${provider}" == "psm3" ] || [ "${provider}" == "socket" ]; then
        daos="no"
    fi
    xpmem="no"
elif [ "\${embedded_ofi}" == "yes" ]; then
    config_extra+=" --disable-psm3"
fi

if [ "${provider}" == "psm2" ] || [ "${provider}" == "psm3" ]; then
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

srun --chdir="\$REMOTE_WS" /bin/bash \${BUILD_SCRIPT_DIR}/test-worker.sh \
    -h \${REMOTE_WS}/_build \
    -i \${OFI_DIR} \
    -c ${compiler} \
    -o ${config} \
    -F \${fast} \
    -d noam \
    -b drop \
    -s auto \
    -p ${provider} \
    -m \${n_jobs} \
    -N "\${neo_dir}" \
    -r \$REL_WORKSPACE/${config_name} \
    -t 2.0 \
    -x ${run_tests} \
    -k \$embedded_ofi \
    -H "\${gpudirect}" \
    -Y "\${ze_native}" \
    -Z "\${ze_dir}" \
    -j "--disable-opencl \${config_extra}" \
    -D \$daos \
    -E \$xpmem \
    -P ${pmix} \
    -a "\$cpu" \
    -O \$ofi_domain \
    -y \$CUSTOM_VERSION_STRING \
    -f \$INSTALL_DIR

if [ "${run_tests}" = "yes" ]; then
    srun cp test/mpi/summary.junit.xml ${config_name}/test/mpi/summary.junit.xml
fi

if [ "${pmix}" = "nopmix" ]; then
    srun --chdir="\$WORKSPACE" /bin/bash \$WORKSPACE/hydra-pmi-proxy-cleanup.sh "\$INSTALL_DIR"
fi

srun rm -f \$INSTALL_DIR/lib/pkgconfig/libfabric.pc
srun mkdir -p \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 'COPYRIGHT' \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 'CHANGES' \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 README \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 README.envvar \$INSTALL_DIR/share/doc/mpich
srun --chdir="\$REMOTE_WS" install -m 0644 doc/mpich/tuning_parameters.md \$INSTALL_DIR/share/doc/mpich
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

                        if (check_config(provider, compiler, config, pmix, flavor) == false) {
                            continue
                        }

                        rpms["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                            node('anfedclx8') {
                                def version = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/drop_version')
                                def release = sh(returnStdout: true, script: 'cat ${HOME}/rpmbuild/release_version')
                                sh(script: """
#!/bin/bash -xe

# Set overlap as default
export SLURM_OVERLAP=1

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
    --define="_pmix ${pmix}" \
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
                        /* We test cxi provider with GPU on Boris */
                        if ("${provider}" != "cxi" && "${provider}" != "all" && "${flavor}" == "gpu") {
                            continue
                        }
                        /* For GPU test, we only test default config */
                        if ("${config}" != "default" && "${flavor}" == "gpu") {
                            continue
                        }
                        /* We don't have a way to automate testing with cxi for non GPU yet */
                        if ("${provider}" == "cxi" && "${flavor}" != "gpu") {
                            continue
                        }
                        if (check_config(provider, compiler, config, pmix, flavor) == false) {
                            continue
                        }
                        /* We currently have no way to install an RPM on a verbs cluster */
                        rpm_tests["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                            def node_name = "anfedclx8-admin"
                            if ("${provider}" == "verbs") {
                                node_name = "anccskl6"
                            }
                            if ("${flavor}" == "gpu") {
                                node_name = "boris"
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

# Set overlap as default
export SLURM_OVERLAP=1

export version=\$(<drop_version)
export release=\$(<release_version)
export job="drop\${version}"
export nodes=1
export TARBALL="mpich-drops.tar.bz2"

# Print out the hostname for debugging logs
hostname

cat > RPM-testing-drop-job.sh << "EOF"
#!/bin/bash -x

srun --chdir="\$WORKSPACE" /bin/bash \${WORKSPACE}/maint/jenkins/scripts/rpm-testing.sh \
    \${job} \${nodes} \${version} \${release} ${provider} ${compiler} ${config} ${pmix} ${flavor} ${testgpu} \$WORKSPACE

EOF

chmod +x RPM-testing-drop-job.sh
tar -xf \$TARBALL

prefix="salloc -J "\$job-${provider}-${compiler}-${config}-${pmix}-${flavor}" -N \${nodes} -t 600"
if [ "${node_name}" == "boris" ]; then
    # Boris requires reservation of GPU nodes before testing. Make sure you reserve the node with reservation name "mpich_drop_pipeline" before the drop!
    prefix="\${prefix} --reservation=mpich_drop_pipeline"
fi

\${prefix} ./RPM-testing-drop-job.sh
""")
                                junit "**/summary.junit.xml"
                                cleanWs()
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
}

if (params.publish_results) {
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

                        if (check_config(provider, compiler, config, pmix, flavor) == false) {
                            continue
                        }

                        rpms_upload["${provider}-${compiler}-${config}-${pmix}-${flavor}"] = {
                            node('anfedclx8') {
                                withCredentials([string(credentialsId: 'artifactory_api_key', variable: 'API_KEY')]) {
                                sh(script: """
#!/bin/bash

version=`cat \${HOME}/rpmbuild/drop_version`
release=`cat \${HOME}/rpmbuild/release_version`

pmix_string=""
dir="drop\${version}.\${release}"
subdir=""

flavor_string=""
if [ "${flavor}" != "regular" ]; then
    flavor_string="-${flavor}"
    subdir="${flavor}"
fi
if [ "${flavor}" == "regular" ]; then
    subdir="regular/${pmix}"
fi
if [ "${pmix}" == "pmix" ]; then
    pmix_string="-pmix"
fi

NAME="mpich-ofi-${provider}-${compiler}-${config}\${pmix_string}\${flavor_string}-drop\${version}"
RPM_NAME="\${NAME}-\${version}-\${release}.x86_64.rpm"

curl -H 'X-JFrog-Art-Api:$API_KEY' -XPUT \
https://af02p-or.devtools.intel.com/artifactory/mpich-aurora-or-local/\$dir/\$subdir/\${RPM_NAME} \
-T \${HOME}/rpmbuild/RPMS/x86_64/\${RPM_NAME}

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
        node('anfedclx8') {
            withCredentials([string(credentialsId: 'artifactory_api_key', variable: 'API_KEY')]) {
                sh(script: """
#!/bin/bash -xe

version=\$(<drop_version)
release=\$(<release_version)
dir="drop\${version}.\${release}"

tag_string="drop\${version}"
if [ "\${release}" != "0" ]; then
    tag_string="\${tag_string}.\${release}"
fi

cp \$HOME/rpmbuild/SOURCES/${tarball_name} .
mv ${tarball_name} mpich-\${tag_string}.tar.bz2

curl -H 'X-JFrog-Art-Api:$API_KEY' -XPUT \
    https://af02p-or.devtools.intel.com/artifactory/mpich-aurora-or-local/\$dir/tarballs/mpich-\${tag_string}.tar.bz2 \
    -T mpich-\${tag_string}.tar.bz2
""")
                cleanWs()
            }
        }
    }
}

if (params.build_rpms) {
    node('anfedclx8') {
        stage('Cleanup Build Directories') {
            sh(script: """rm -rf \$HOME/rpmbuild/BUILD \$HOME/rpmbuild/BUILDROOT""")
        }
    }
}
