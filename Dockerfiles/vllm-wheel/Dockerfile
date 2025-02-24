###
#
# Build package wheel

# Set enviornment
#
ARG TOOLCHAIN_VERSION="undefined"
FROM ghcr.io/vllmd/toolchain:${TOOLCHAIN_VERSION} AS vllm_wheel
ARG TOOLCHAIN_VERSION
ENV TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION}"
ARG PACKAGE_VERSION="undefined"
ARG BUILD_NPROC="undefined"
ENV VERBOSE=1

# syntax=docker/dockerfile:1

# Set labels
#
LABEL "com.computelify.vendor"="Computelify, Inc."
LABEL "com.computelify.product"="The VLLMD inferenicng platform."
LABEL "com.computelify.version"="${PACKAGE_VERSION}"
LABEL "com.computelify.component"="vllm-wheel"


###
#
# Obtain source code

# list of submodules 
#
# either generate wheels independently, or integrate into this builde.
# we do need to build flash-attention now with AOT enabled.
# https://github.com/google/benchmark.git
# https://github.com/catchorg/Catch2.git
# https://github.com/ROCm/composable_kernel.git
# https://github.com/NVIDIA/cutlass.git
# https://github.com/vllm-project/flash-attention.git
# https://github.com/flashinfer-ai/flashinfer.git
# https://github.com/apwojcik/getopt.git
# https://github.com/google/googletest.git
# https://github.com/microsoft/mscclpp.git
# https://github.com/wjakob/nanobind
# https://github.com/NVIDIA/nvbench.git
# https://github.com/oneapi-src/oneDNN.git
# https://github.com/gabime/spdlog.git
# https://github.com/vllm-project/vllm.git

# obtain vllm source code
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
  "https://github.com/vllm-project/vllm.git" \
  "${WORKSPACE_SOURCE_PATH}/vllm"


# Build wheel
#
RUN rm --force "${WORKSPACE_SOURCE_PATH}/vllm/setup.py"
COPY "README.md" "${WORKSPACE_SOURCE_PATH}/vllm"
COPY "pyproject.toml" "${WORKSPACE_SOURCE_PATH}/vllm"
RUN rm --recursive --force "${WORKSPACE_SOURCE_PATH}/.venv"
WORKDIR "${WORKSPACE_SOURCE_PATH}"
RUN uv python install "3.11"
RUN uv venv --python "3.11" --python-preference "only-managed"
WORKDIR "${WORKSPACE_SOURCE_PATH}/vllm"
RUN uv pip install --requirement "${WORKSPACE_SOURCE_PATH}/vllm/requirements-build.txt"
RUN uv build --wheel --python-preference "only-managed" --python "3.11" --out-dir "${WORKSPACE_TARGET_PATH}"


# Emit wheel
#
FROM scratch
COPY --from=vllm_wheel /workspace/target /
