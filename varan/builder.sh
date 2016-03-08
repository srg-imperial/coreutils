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


PROJECT="coreutils"

# The folder of 'this' script
BUILDER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd ${BUILDER_DIR}/.. && pwd )"

ROOT_DIR="${HOME}/.varan_experimental"
INSTALL_DIR="${ROOT_DIR}/${PROJECT}"
BIN_DIR="${ROOT_DIR}/bin"

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

ldconfig -p | grep libasan &> /dev/null
if [ $? -ne 0 ]; then
    echo "libasan is not installed!"
    exit 1
fi

which vx &> /dev/null
if [ $? -ne 0 ]; then
    echo "varan (vx command) is not installed or not in PATH!"
    exit 1
fi

# This is step 2 from the description
echo "Preparing for building with asan"
cp -r ${REPO_DIR}/${PROJECT} ${REPO_DIR}/${PROJECT}_build
cd ${REPO_DIR}/${PROJECT}_build

# Store old values. We will need them to build a normal version
old_CFLAGS=${LDFLAGS}
old_CFLAGS=${CXXFLAGS}
old_CFLAGS=${CFLAGS}

export LDFLAGS="${LDFLAGS} -fsanitize=address -fno-omit-frame-pointer -fsanitize-recover"
export CXXFLAGS="${CXXFLAGS} -g -fsanitize=address -fno-omit-frame-pointer -fsanitize-recover"
export CFLAGS="${CFLAGS} -g -fsanitize=address -fno-omit-frame-pointer -fsanitize-recover"

echo "Building with asan"
echo "You can see the building logs in: ${REPO_DIR}/${PROJECT}_asan.log"
echo "This usually takes awhile. Please wait..."
./configure --prefix=${INSTALL_DIR} &> ${REPO_DIR}/${PROJECT}_asan.log
make $>> ${REPO_DIR}/${PROJECT}_asan.log
make install &>> ${REPO_DIR}/${PROJECT}_asan.log
echo "Building with asan is done"

# We just keep the executable binaries. We discard everything else
mkdir ${INSTALL_DIR}_asan
mv ${INSTALL_DIR}/bin ${INSTALL_DIR}_asan
rm -rf ${INSTALL_DIR}

# Prepare for next building
echo "Preparing for noram building"
cd ${REPO_DIR}
rm -rf ${REPO_DIR}/${PROJECT}_build
cp -r ${REPO_DIR}/${PROJECT} ${REPO_DIR}/${PROJECT}_build
cd ${REPO_DIR}/${PROJECT}_build

export LDFLAGS="${old_LDFLAGS}"
export CXXFLAGS="${old_CXXFLAGS}"
export CFLAGS="${old_CFLAGS}"

echo "Normal building"
echo "You can see the building logs in: ${REPO_DIR}/${PROJECT}_normal.log"
echo "This usually takes awhile. Please wait..."
./configure --prefix=${INSTALL_DIR} &> ${REPO_DIR}/${PROJECT}_normal.log
make &>> ${REPO_DIR}/${PROJECT}_normal.log
make install &>> ${REPO_DIR}/${PROJECT}_normal.log
echo "Normal building is done"

rm -rf ${REPO_DIR}/${PROJECT}_build
cd ${REPO_DIR}

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
