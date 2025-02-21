#!/usr/bin/env bash
#

###
#
# Configure environment

# configure package
#
PACKAGE_OWNER="vllmd"
PACKAGE_NAME="toolchain"
PACKAGE_VERSION=$(date "+%Y%m%d")
BUILD_TIMESTAMP=$(date "+%Y%m%d%H%M%S")
BUILD_PLATFORM="linux/amd64"
TAG="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}-${BUILD_TIMESTAMP}"
TAG_SHORT="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}"
SHELL="$(which bash)"

# configure buildkit
#
export BUILDKIT_TTY_LOG_LINES=1000000
export BUILDKIT_EXPERIMENTAL=true
export BUILDKIT_COLORS="run=green:warning=yellow:error=red:cancel=255,165,0"

# configure logging
#
LOGS_PATH="logs"
TARGET_PATH="target"

LOG_FILEPATH="${LOGS_PATH}/build-${BUILD_TIMESTAMP}.log"
LOG_TIMING_FILEPATH="${LOGS_PATH}/timing-${BUILD_TIMESTAMP}.log"

# create paths
#
mkdir --parents "${TARGET_PATH}"
mkdir --parents "${LOGS_PATH}"

# build and emit package
#
script \
    --quiet \
    --return \
    --logging-format "advanced" \
    --log-io "${LOG_FILEPATH}" \
    --log-timing "${LOG_TIMING_FILEPATH}" \
    --echo "always" \
    --command "nerdctl build \
          --debug-full \
          --label nerdctl/bypass4netns=true \
          --no-cache \
          --progress plain \
          --tag ${TAG} \
          --tag ${TAG_SHORT} \
          --platform ${BUILD_PLATFORM} \
          --build-arg TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION} \
          --build-arg PACKAGE_VERSION=${PACKAGE_VERSION} \
          --build-arg BUILD_TIMESTAMP=${BUILD_TIMESTAMP} \
          --build-arg BUILD_NPROC=$(nproc) . "


nerdctl push "${TAG}"
nerdctl push "${TAG_SHORT}"

BUILD_STATUS=$?
