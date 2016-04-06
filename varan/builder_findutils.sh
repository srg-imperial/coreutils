#!/bin/bash

# The idea is:
#   1) Do checks that the appropriate tools exist (libasan, vx)
#   2) Build the projects (e.g. coreutils) locally (both normally and with asan)
#   3) Install the asan project
#   4) Move only the /bin dir in an other special directory
#   5) Delete the install dir (so to discard other asan stuff)
#   6) Install the normal project
#   7) Install the varan invoke script under ${BIN_DIR}
#   8) Export ${BIN_DIR} to the user's ${PATH}
# Extras and TODO:
#   *) Parallelize building
#   *) Generalize building as different project might have different commands

set -o errexit

############ GLOBALS ############
PROJECT="findutils"

# The folder of 'this' script
BUILDER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd ${BUILDER_DIR}/.. && pwd )"

ROOT_DIR="${HOME}/.varan_experimental"
INSTALL_DIR="${ROOT_DIR}/${PROJECT}"
BIN_DIR="${ROOT_DIR}/bin"

############ FUNCTIONS ############
print_failure() {
  local file=$1

  echo ""
  echo "We got an error:"
  tput setaf 1;
  tail -n10 ${file}
  tput sgr0;
  exit 1
}

print_vx_install() {
  echo "varan (vx command) is not installed or not in PATH!"
  exit 1
}

print_asan_install() {
  echo "libasan is not installed!"
  exit 1
}

############ MAIN ############
if [ ! -d "${ROOT_DIR}" ] || [ ! -d "${ROOT_DIR}"/bin ]; then
  mkdir -p ${ROOT_DIR}/bin
fi

echo "Scanning for dependences and old installations"
# Do some environment checks
# TODO: Do some more checks
if [ -d ${INSTALL_DIR} ]; then
  echo "Project: ${PROJECT} already exists!"
  echo "Please delete ${INSTALL_DIR} and ${INSTALL_DIR}_asan, to reinstall."
  exit 1
fi

ldconfig -p | grep libasan &> /dev/null || print_asan_install

which vx &> /dev/null || print_vx_install

# This is step 2 from the description
echo "Preparing for building with asan"
tar xf ${PROJECT}.tar.xz
cd ${REPO_DIR}/${PROJECT}_build

# Store old values. We will need them to build a normal version
old_LDFLAGS=${LDFLAGS}
old_CXXFLAGS=${CXXFLAGS}
old_CFLAGS=${CFLAGS}

# -fsanitize-recover is not supported by the default GCC in ubunut 14.04
export LDFLAGS="${LDFLAGS} -fsanitize=address -fno-omit-frame-pointer"
export CXXFLAGS="${CXXFLAGS} -g -fsanitize=address -fno-omit-frame-pointer"
export CFLAGS="${CFLAGS} -g -fsanitize=address -fno-omit-frame-pointer"

echo "Building with asan"
echo "You can see the building logs in: ${REPO_DIR}/${PROJECT}_asan.log"
echo "This usually takes awhile. Please wait..."
LOG_FILE=${REPO_DIR}/${PROJECT}_asan.log
./configure --prefix=${INSTALL_DIR} &> ${LOG_FILE} || print_failure ${LOG_FILE}
make &>> ${LOG_FILE} || print_failure ${LOG_FILE}
make install &>> ${LOG_FILE} || print_failure ${LOG_FILE}
echo "Building with asan is done"

# We just keep the executable binaries. We discard everything else
mkdir ${INSTALL_DIR}_asan
mv ${INSTALL_DIR}/bin ${INSTALL_DIR}_asan
rm -rf ${INSTALL_DIR}

# Cleanup
cd ${REPO_DIR}
rm -rf ${REPO_DIR}/${PROJECT}_build

# Prepare for next building
echo "Preparing for normal building"
tar xf ${PROJECT}.tar.xz
cd ${REPO_DIR}/${PROJECT}_build

export LDFLAGS="${old_LDFLAGS}"
export CXXFLAGS="${old_CXXFLAGS}"
export CFLAGS="${old_CFLAGS}"

echo "Normal building"
echo "You can see the building logs in: ${REPO_DIR}/${PROJECT}_normal.log"
echo "This usually takes awhile. Please wait..."
LOG_FILE=${REPO_DIR}/${PROJECT}_normal.log
./configure --prefix=${INSTALL_DIR} &> ${LOG_FILE} || print_failure ${LOG_FILE}
make &>> ${LOG_FILE} || print_failure ${LOG_FILE}
make install &>> ${LOG_FILE} || print_failure ${LOG_FILE}
echo "Normal building is done"

# Cleanup
cd ${REPO_DIR}
rm -rf ${REPO_DIR}/${PROJECT}_build

# Setup commands with varan
echo "Setting up Varan commands"
for bin in ${INSTALL_DIR}/bin/*; do
  name=$(basename ${bin})

  script="#!/usr/bin/env bash\n\n            \
  ASAN_OPTIONS=\"allow_user_segv_handler=1\" \
  vx ${INSTALL_DIR}/bin/${name} ${INSTALL_DIR}_asan/bin/${name} -- \$@"

  echo -e ${script} > ${BIN_DIR}/${name}
  chmod 750 ${BIN_DIR}/${name}
done

echo "Use the following command to start playing with Varan :)"
echo "export PATH=${BIN_DIR}:\$PATH"
