# syntax=docker/dockerfile:1
FROM debian:bookworm-slim AS vllm-stage-0

# Configure enviroonment
#
ENV WORKSPACE_SOURCE_PATH="/workspace/source"
ENV UV_VERSION="0.5.26"
ENV PATH="/bin:/usr/bin:/usr/local/bin:/runtime/.venv/bin"

# Create paths
#
RUN mkdir --parents /workspace/source
RUN mkdir --parents /workspace/install
RUN mkdir --parents /workspace/cache

# install uv, curl
#
COPY vllm-0.7.3-cp311-abi3-linux_x86_64.whl /workspace/install
RUN apt-get --yes update
RUN apt-get --yes install curl
WORKDIR /usr/local/bin
RUN curl --output "/usr/local/bin/uv.tar.gz" --location "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz"
RUN tar --extract --file uv.tar.gz
RUN mv "/usr/local/bin/uv-x86_64-unknown-linux-gnu/uv"* "/usr/local/bin"

# install wheel
# 
ENV UV_CACHE_DIR="/workspace/uv-cache"
ENV UV_NO_CONFIG="1"
ENV UV_PYTHON_DOWNLOADS="manual"
ENV UV_PYTHON_VERSION="3.11"
ENV UV_PYTHON_INSTALL_DIR="/runtime/"
ENV UV_PYTHON_PREFERENCE="only-managed"
ENV UV_LINK_MODE="copy"
ENV UV_COMPILE_BYTECODE="1"
ENV UV_STRICT="1"
ENV UV_NO_BUILD="1"

WORKDIR /runtime
RUN uv python install 3.11
RUN uv venv
RUN uv python list
RUN uv pip install /workspace/install/vllm-0.7.3-cp311-abi3-linux_x86_64.whl
RUN uv pip install accelerate
RUN uv pip install hf_transfer
RUN uv pip install bitsandbytes
RUN uv pip install boto3
RUN uv pip install timm
RUN uv pip install modelscope
RUN uv pip install runai-model-streamer
RUN uv pip install runai-model-streamer[s3]
RUN uv pip install https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2/flashinfer_python-0.2.2+cu124torch2.5-cp38-abi3-linux_x86_64.whl

# manually override version information
COPY _version.py /runtime/.venv/lib/python3.11/site-packages/vllm/_version.py

# Audit apt and whl packages to eliminate pesky telemetry.
# 
RUN uv pip list
RUN apt list --installed

#
FROM debian:bookworm-slim

# Shameful this needs to be set.
#
# The queestion should be:
#   "Would anyone intentionally enable tracking?"
#
ENV DO_NOT_TRACK="1"
ENV NO_TELEMeTRY="1"
ENV ANALYTICS_OPT_OUT="1"
ENV TELEMETRY_DISABLED="1"
ENV DISABLE_ANALYTICS="1"

# Disable corporate tracking
#
ENV VLLM_NO_USAGE_STATS="1"
ENV VLLM_DO_NOT_TRACK="1"
ENV VLLM_USAGE_SOURCE="vllmd.com.component.vllm"
ENV HF_HUB_DISABLE_TELEMETRY="1"

# Audit the codebase for undisclosed tracking.
#
ENV ACCELERATE_DISABLE_TELEMETRY="1"
ENV AWS_CSM_ENABLED="false"
ENV DISABLE_TELEMETRY="1"
ENV HF_DATASETS_DISABLE_TELEMETRY="1"
ENV HF_HUB_DISABLE_TELEMETRY="1"
ENV MODELSCOPE_DISABLE_TELEMETRY="1"
ENV NVIDIA_TELEMETRY_DISABLE="1"
ENV NVTE_NO_INIT_TELEMETRY="1"
ENV PYTORCH_COLLECT_USAGE_METRICS="0"
ENV PYTORCH_DISABLE_HIP_VERSION_CHECK="1"
ENV PYTORCH_NO_NVML="1" 
ENV RAY_DISABLE_USAGE_STATS="1"
ENV TRANSFORMERS_NO_ADVISORY_WARNINGS="1"
ENV TQDM_DISABLE="1"

# Configure environment
# 
ENV UV_CACHE_DIR="/workspace/uv-cache"
ENV UV_PYTHON_VERSION="3.11"
ENV UV_PYTHON_DOWNLOADS="never"
ENV UV_PYTHON_PREFERENCE="only-managed"
ENV UV_NO_CONFIG="1"
ENV UV_LINK_MODE="copy"
ENV UV_OFFLINE="1"
ENV UV_COMPILE_BYTECODE="1"
ENV UV_NO_BUILD="1"
ENV HF_HUB_ENABLE_HF_TRANSFER="1"
ENV PATH="${PATH}:/runtime/.venv/bin"

COPY --from=vllm-stage-0 /runtime /runtime
RUN du -h /runtime
ENTRYPOINT ["/runtime/.venv/bin/vllm", "serve"]
