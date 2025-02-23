#!/usr/bin/env bash
#

# Build configuration
#
TOOLCHAIN_VERSION="v20250221"
PACKAGE_OWNER="vllmd"
PACKAGE_NAME="vllm-wheel"
PACKAGE_VERSION="0.7.3"
BUILD_TIMESTAMP=$(date "+%Y%m%d%H%M%S")
BUILD_PLATFORM="linux/amd64"
TAG_FULL="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}-${BUILD_TIMESTAMP}"
TAG_SHORT="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}"

# BuildKit configuration
#
export BUILDKIT_EXPERIMENTAL="true"
export BUILDKIT_COLORS="run=green:warning=yellow:error=red:cancel=255,165,0"

# Logging configuration
#
LOGS_PATH="logs"
TARGET_PATH="target"

LOG_BUILD_FILEPATH="${LOGS_PATH}/${BUILD_TIMESTAMP}-build.log"
LOG_TIMING_FILEPATH="${LOGS_PATH}/${BUILD_TIMESTAMP}-timing.log"

# Create required directories
#
mkdir --parents "${LOGS_PATH}"
mkdir --parents "${TARGET_PATH}"

# Build while creating record
#
script \
  --return \
  --logging-format "advanced" \
  --log-io "${LOG_BUILD_FILEPATH}" \
  --log-timing "${LOG_TIMING_FILEPATH}" \
  --echo "always" \
  --command "nerdctl build \
          --debug-full \
          --no-cache \
          --progress plain \
          --tag ${TAG_FULL} \
          --tag ${TAG_SHORT} \
          --platform ${BUILD_PLATFORM} \
          --build-arg TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION} \
          --build-arg PACKAGE_VERSION=${PACKAGE_VERSION} \
          --build-arg BUILD_TIMESTAMP=${BUILD_TIMESTAMP} \
          --build-arg BUILD_NPROC=$(nproc) \
          --output=type=local,dest=${TARGET_PATH} ."

BUILD_STATUS=$?
exit "${BUILD_STATUS}"
