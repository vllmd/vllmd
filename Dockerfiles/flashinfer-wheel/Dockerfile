###
#
# Build package wheel

# Set enviornment
#
ARG TOOLCHAIN_VERSION="undefined"
FROM ghcr.io/vllmd/toolchain:${TOOLCHAIN_VERSION} AS flashinfer_wheel
ARG TOOLCHAIN_VERSION
ENV TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION}"
ARG PACKAGE_VERSION="undefined"
ARG BUILD_NPROC="undefined"
ENV VERBOSE="1"

# syntax=docker/dockerfile:1

# Set labels
#
LABEL "com.computelify.vendor"="Computelify, Inc."
LABEL "com.computelify.product"="The VLLMD inferenicng platform."
LABEL "com.computelify.version"="${PACKAGE_VERSION}"
LABEL "com.computelify.component"="flashinfer-wheel"


# obtain flashinfer source code
#
RUN git -c fetch.parallel=8 \
    -c advice.detachedHead=false \
    clone \
    --depth 1 \
    --jobs "${BUILD_NPROC}" \
    --single-branch \
    --recurse-submodules \
    --shallow-submodules \
    --branch "v${PACKAGE_VERSION}" \
    "https://github.com/flashinfer-ai/flashinfer.git" \
    "${WORKSPACE_SOURCE_PATH}/flashinfer"


# TODO(sdake) consolidate the details
# forgive the cargo-copy-cult, although I wrote the first copy.
RUN rm --recursive --force "${WORKSPACE_SOURCE_PATH}/.venv"
ENV UV_CACHE_DIR="/workspace/uv-cache"
ENV UV_NO_CONFIG="1"
ENV UV_PYTHON_DOWNLOADS="manual"
ENV UV_PYTHON_VERSION="3.11"
ENV UV_PYTHON_INSTALL_DIR="${WORKSPACE_SOURCE_PATH}"
ENV UV_PYTHON_PREFERENCE="only-managed"
ENV UV_LINK_MODE="copy"
ENV UV_COMPILE_BYTECODE="1"
ENV UV_STRICT="1"
ENV UV_NO_BUILD="1"
ENV FLASHINFER_ENABLE_AOT="1"
ENV TORCH_CUDA_ARCH_LIST="8.6"
ENV CMAKE_CUDA_ARCHITECTURES="86"

# Install environment
#
# TODO(sdake)
# This really needs to be in the toolchain image.
# indepedently there needs to be a baseline image for running python workloads.
WORKDIR "${WORKSPACE_SOURCE_PATH}"
RUN uv python install "3.11"
RUN uv venv

# Build wheel
#
WORKDIR "${WORKSPACE_SOURCE_PATH}/flashinfer"
RUN uv build --wheel --out-dir "${WORKSPACE_TARGET_PATH}"


# Emit wheel
#
FROM scratch
COPY --from=flashinfer_wheel /workspace/target /
