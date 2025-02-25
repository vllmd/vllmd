#!/usr/bin/env bash
#

# Build configuration
#
TOOLCHAIN_VERSION="v20250221"
PACKAGE_OWNER="vllmd"
PACKAGE_NAME="vllm"
PACKAGE_VERSION="0.7.3"
BUILD_TIMESTAMP=$(date "+%Y%m%d%H%M%S")
BUILD_PLATFORM="linux/amd64"
TAG_FULL="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}-${BUILD_TIMESTAMP}"
TAG_SHORT="ghcr.io/${PACKAGE_OWNER}/${PACKAGE_NAME}:v${PACKAGE_VERSION}"

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
    --command \
    "nerdctl build \
        --no-cache \
        --progress plain \
        --platform=${BUILD_PLATFORM} \
        --build-arg TOOLCHAIN_VERSION=${TOOLCHAIN_VERSION} \
        --build-arg PACKAGE_VERSION=${PACKAGE_VERSION} \
        --build-arg BUILD_TIMESTAMP=${BUILD_TIMESTAMP} \
        --build-arg NPROC=$(nproc) \
        --output type=image,name=${TAG_FULL},name=${TAG_SHORT},compression=zstd,force-compression=true,compresion-level=21,push=true,inline-cache=false ."

BUILD_STATUS=$?
exit "${BUILD_STATUS}"
