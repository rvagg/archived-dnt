#!/bin/bash

##############################################################
# DNT: Run tests in Docker containers for many Node versions #
##############################################################

CONFIG_FILE=".dntrc"
OUTPUT_PREFIX=""
COPYDIR=$(pwd)
# How many tests can we run at once without making the computer grind to a halt
# or causing other unwanted resource problems:
SIMULTANEOUS=$(getconf _NPROCESSORS_ONLN)
COPY_CMD="rsync -aAXx --delete --exclude .git --exclude build /dnt-src/ /dnt/"
LOG_OK_CMD="tail -1"
IOJS_VERSIONS=

if [ -f $CONFIG_FILE ]; then
  source ./$CONFIG_FILE
else
  echo "You must have a ${CONFIG_FILE} in the current directory"
  exit 1
fi

NODE_VERSIONS="$NODE_VERSIONS $IOJS_VERSIONS"
# The versions of Node to test, this assumes that we have a Docker image
# set up with the name "node_dev/<version>"
#NODE_VERSIONS=$(cat ${__dirname}/node_versions.list)

if [ $# -gt 0 ] ; then
  NODE_VERSIONS=$*
  echo "Using Node versions: ${NODE_VERSIONS}"
fi

if [ "X${NODE_VERSIONS}" == "X" ]; then
  echo "You must set up a NODE_VERSIONS list in your ${CONFIG_FILE}"
  exit 1
fi

if [ "X${TEST_CMD}" == "X" ]; then
  echo "You must set up a TEST_CMD in your ${CONFIG_FILE}"
  exit 1
fi

START_TS=$(date +%s)

test_node() {
  local OUT=/tmp/${OUTPUT_PREFIX}dnt-${NV}.out
  local TYPE=$1
  local NV=$2
  local ID="node_dev"

  docker inspect "$ID" &> /dev/null
  if [[ $? -ne 0 ]]; then
    echo -e "\033[31mCould not find container, please run setup-dnt\033[22m]\033[39m"
    return
  fi

  # Run test in a Docker container
  RUNCMD="/bin/su -s /bin/bash dnt -c '. /nvm/nvm.sh && ${COPY_CMD}"
  if [ "X${APT_INSTALL}" != "X" ]; then
    RUNCMD="apt-get update && apt-get install -y ${APT_INSTALL} && ${RUNCMD}"
  fi
  RUNCMD="${RUNCMD} && nvm use ${NV} && ${TEST_CMD}'"

  DOCKER_EXEC="docker run -i --rm"

  if [ "X${RUN_TIMEOUT}" != "X" ]; then
    DOCKER_EXEC="timeout $RUN_TIMEOUT docker run -i --rm"
  fi

  if [ "${CONSOLE_LOG}" == "true" ]; then
    $DOCKER_EXEC -v ~/.npm/:/dnt/.npm/ -v ${COPYDIR}:/dnt-src/:ro $ID /bin/bash -c "$RUNCMD" 2>&1 | tee $OUT
  else
    $DOCKER_EXEC -v ~/.npm/:/dnt/.npm/ -v ${COPYDIR}:/dnt-src/:ro $ID /bin/bash -c "$RUNCMD" &> $OUT
  fi 

  # Print status

  LAST_LINE=$(eval "cat /tmp/${OUTPUT_PREFIX}dnt-${NV}.out | $LOG_OK_CMD")

  printf "${TYPE}@\033[1m\033[33m%-8s\033[39m\033[22m: " $NV
  if [[ $LAST_LINE  == "ok" ]]; then
    echo -ne "\033[1m\033[32mPASS\033[39m\033[22m"
  elif [[ $LAST_LINE == "# fail 0" ]]; then
    echo -ne "\033[1m\033[32mPASS\033[39m\033[22m"
  else
    echo -ne "\033[1m\033[31mFAIL\033[39m\033[22m"
  fi
  echo -e " \033[3mwrote output to ${OUT}\033[23m"
}

# Run all tests
_C=0
for NV in $NODE_VERSIONS; do
  test_node "node" $NV &
  # Small break between each start, gives Docker breathing room
  sleep 0.5

  # Crude limiting on the number of simultaneous runs
  let _C=_C+1
  if [[ $((_C % ${SIMULTANEOUS})) == 0 ]]; then
    wait
  fi
done

wait

END_TS=$(date +%s)
DURATION=$((END_TS-START_TS))
VERSIONS=$(echo $NODE_VERSIONS | wc -w)

echo "Took ${DURATION}s to run ${VERSIONS} versions of Node"
