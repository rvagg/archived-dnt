#!/bin/bash

##########################################################
# Set up Docker containers with basic dev tools and Node #
##########################################################

CONFIG_FILE=".dntrc"
# For `make -j X`
BUILD_JOBS=$(getconf _NPROCESSORS_ONLN)
NODE_VERSIONS=
IOJS_VERSIONS=

if [ -f $CONFIG_FILE ]; then
  source ./$CONFIG_FILE
else
  echo "You must have a ${CONFIG_FILE} in the current directory"
  exit 1
fi

if [ $# -gt 0 ] ; then
  NODE_VERSIONS=$*
  echo "Using Node.js versions: ${NODE_VERSIONS}"
fi

if [ "X${NODE_VERSIONS}" == "X" ]; then
  echo "You must set up a NODE_VERSIONS list in your ${CONFIG_FILE}"
  exit 1
fi

# Simple setup function for a container:
#  setup_container(image id, base image, commands to run to set up)
setup_container() {
  local ID=$1
  local BASE=$2
  local RUN=$3

  # Does this image exist? If yes, ignore
  docker inspect "$ID" &> /dev/null
  if [[ $? -eq 0 ]]; then
    echo "Found existing container [$ID]"
    return
  fi

  # No such image, so make it
  echo "Did not find container [$ID], creating..."
  docker run -i $BASE /bin/bash -c "$RUN"
  sleep 2
  docker commit $(docker ps -l -q) $ID
}

# A basic dev image with the build tools needed for Node
# adding "universe" to make it easier to add additional tools for
# builds that need it
setup_container "dev_base" "ubuntu:14.04" " \
  apt-get update && \
  apt-get install -y git rsync wget && \
  adduser --gecos dnt --home /dnt/ --disabled-login dnt && \
  echo "dnt:dnt" | chpasswd
"

docker inspect node_dev &> /dev/null
  if [[ $? -eq 0 ]]; then
    docker rmi --force node_dev
  fi

INSTALL="echo 'Starting Installs'"
for NV in $NODE_VERSIONS $IOJS_VERSIONS; do
  INSTALL="$INSTALL && nvm install $NV"
done

setup_container "node_dev" "dev_base" " \
  wget https://raw.githubusercontent.com/creationix/nvm/v0.29.0/install.sh
  NVM_DIR='/nvm' bash install.sh
  source /nvm/nvm.sh
  $INSTALL
"