###
#
#

FROM debian:bookworm AS toolchain-build
ARG PACKAGE_VERSION="undefined"
ENV PACKAGE_VERSION="${PACKAGE_VERSION}"

LABEL "com.computelify.vendor"="Computelify, Inc."
LABEL "com.computelify.product"="The vllmd toolchain image"
LABEL "com.computelify.version"="${PACKAGE_VERSION}"
LABEL "com.computelify.component"="toolchain" 


# Set global environment variables
#
ENV WORKSPACE_VENV_PATH="/workspace/source/.venv"
ENV WORKSPACE_BUILD_PATH="/workspace/build"
ENV WORKSPACE_SOURCE_PATH="/workspace/source"
ENV WORKSPACE_TARGET_PATH="/workspace/target"
ENV WORKSPACE_TEMPORARY_PATH="/workspace/temporary"
ENV RUSTUP_HOME="/usr/local/lib/rustup"
ENV CARGO_HOME="/usr/local/lib/cargo"
ENV TMPDIR="/workspace/temporary"
ENV PYTHON="${WORKSPACE_VENV_PATH}/bin/python3"
ENV PYTHON_EXECUTABLE="${WORKSPACE_VENV_PATH}/bin/python3"
ENV Python_EXECUTABLE="${WORKSPACE_VENV_PATH}/bin/python3"
ENV DEBIAN_VERSION="12"
ENV MKL_VERSION="2024.2"
ENV CUDA_VERSION="12-4"
ENV CUDA_HOME="/usr/local/cuda-12.4"
ENV NVTX3_DIR="${CUDA_HOME}/targets/x86_64-linux/lib"
ENV RUST_VERSION="1.84.0"
ENV GO_VERSION="1.23.5"
ENV UV_VERSION="0.5.26"
ENV RUST_ARCH="x86_64"
ENV TARGET_ARCH="amd64"
ENV TORCH_CUDA_ARCH_LIST="8.0;8.6;8.7"
ENV CUDA_ARCHS="${TORCH_CUDA_ARCH_LIST}"
ENV NVIDIA_DRIVER_CAPABILITIES="compute,utility"
ENV NVIDIA_VISIBLE_DEVICES="all"
ENV PATH="${CUDA_HOME}/bin:${CARGO_HOME}/bin:/usr/local/go/bin;${WORKSPACE_VENV_PATH}/bin:${PATH}"
ENV LIBRARY_PATH="${CUDA_HOME}/targets/x86_64-linux/lib/stubs:${CUDA_HOME}/lib:${CUDA_HOME}/lib64"
ENV DEBIAN_FRONTEND="noninteractive"
ENV CMAKE_BUILD_TYPE="Release"
ENV LIBSECCOMP_LINK_TYPE="static"
ENV LIBSECCOMP_LIB_PATH="/usr/lib"
ENV LIBCAPNG_LINK_TYPE="static"
ENV LIBCAPNG_LIB_PATH="/usr/lib"
ENV MKL_ROOT="/opt/intel/oneapi/mkl/${MKL_VERSION}/lib/intel64"
ENV MKL_MODEL="ilp64"
ENV MKL_LIBRARIES="--linker-arg,--start-group;${MKL_ROOT}/libmkl_intel_${MKL_MODEL}.a;${MKL_ROOT}/libmkl_gnu_thread.a;${MKL_ROOT}/libmkl_core.a;--linker-arg,--end-group"
ENV ZSTD_CLEVEL="18"
ENV ZSTD_NBTHREADS="16"


# Configure apt
#
RUN echo 'APT::Get::Assume-Yes "true";' >> /etc/apt/apt.conf.d/99-minimal-install
RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/99-minimal-install
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99-minimal-install
RUN echo 'APT::Install-Documentation "false";' >> /etc/apt/apt.conf.d/99-minimal-instal
RUN echo 'APT::Install-Changelogs "false";' >> /etc/apt/apt.conf.d/99-minimal-install
RUN echo 'APT::Install-APT::Install-Weak-Recommends "false";' >> /etc/apt/apt.conf.d/99-minimal-install


# Create workspace directories
#
WORKDIR /workspace
RUN mkdir --parents "${WORKSPACE_SOURCE_PATH}/workspace/source"
RUN mkdir --parents "${WORKSPACE_BUILD_PATH}/workspace/build"
RUN mkdir --parents "${WORKSPACE_TARGET_PATH}/workspace/target"
RUN mkdir --parents "${WORKSPACE_TEMPORARY_PATH}/workspace/temporary"


# Install industry-standard linux toolchain
#
RUN apt-get update
RUN apt-get install apt-utils
RUN apt-get install build-essential
RUN apt-get install ca-certificates
RUN apt-get install git
RUN apt-get install gpg
RUN apt-get install curl 
RUN apt-get install pkg-config
RUN apt-get install zstd 
RUN apt-get install dpkg
RUN apt-get install dpkg-dev
RUN apt-get install liblzma-dev
RUN apt-get install libnuma-dev
RUN apt-get install libssl-dev
RUN apt-get install libzstd-dev 
RUN apt-get install libucx-dev
RUN apt-get install libmpfr-dev
RUN apt-get install libgmp3-dev
RUN apt-get install libfftw3-dev
RUN apt-get install libjpeg-dev
RUN apt-get install libpng-dev
RUN apt-get install gperf
RUN apt-get install musl
RUN apt-get install musl-tools
RUN apt-get install musl-dev
RUN apt-get install bindgen
RUN apt-get install debhelper-compat
RUN apt-get install linux-libc-dev
RUN apt-get install autoconf
RUN apt-get install automake
RUN apt-get install libtool
RUN apt-get install m4
RUN apt-get install make
RUN apt-get install zlib1g
RUN apt-get install liblzma-dev
RUN apt-get install libzstd-dev
RUN apt-get install cmake
RUN apt-get install ninja-build


# Install uv python dependency manager
#
WORKDIR /usr/local/bin
RUN curl --output "/usr/local/bin/uv.tar.gz" --location "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz"
RUN tar --extract --file uv.tar.gz
RUN mv "/usr/local/bin/uv-x86_64-unknown-linux-gnu/uv"* "/usr/local/bin"


# Install NVIDIA toolchain
#
RUN curl --location --output "cuda-keyring_1.1-1_all.deb" "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb"
RUN dpkg --install "cuda-keyring_1.1-1_all.deb"
RUN apt-get install software-properties-common
RUN add-apt-repository contrib
RUN apt-get update
RUN apt-get install cuda-cudart-dev-12-4
RUN apt-get install cuda-libraries-12-4
RUN apt-get install cuda-nvcc-12-4
RUN apt-get install cuda-nvrtc-12-4
RUN apt-get install cuda-nvrtc-dev-12-4
RUN apt-get install cuda-nvtx-12-4
RUN apt-get install cuda-runtime-12-4
RUN apt-get install libcuda1
RUN apt-get install libcudadebugger1
RUN apt-get install libnvidia-ptxjitcompiler1
RUN apt-get install cuda-toolkit-12-4
RUN apt-get install cudnn9
RUN apt-get install libcublas-12-4
RUN apt-get install libcublas-dev-12-4
RUN apt-get install libcudnn9-cuda-12
RUN apt-get install libcudnn9-dev-cuda-12
RUN apt-get install libcufile-12-4
RUN apt-get install libcufile-dev-12-4
RUN apt-get install libcusparse-12-4
RUN apt-get install libcusparse-dev-12-4
RUN apt-get install libcusparselt0
RUN apt-get install libcusparselt-dev
RUN apt-get install clang-19
RUN apt-get install clang-19-doc
RUN apt-get install clang-19-examples
RUN apt-get install clang-format-19
RUN apt-get install clang-tidy-19
RUN apt-get install clang-tools-19
RUN apt-get install libclang-19-dev
RUN apt-get install libclang-common-19-dev
RUN apt-get install libclang-cpp19
RUN apt-get install libclang-cpp19-dev
RUN apt-get install libclang-rt-19-dev-wasm32
RUN apt-get install libclang-rt-19-dev-wasm32
RUN apt-get install libclang1-19
RUN update-alternatives --set cuda /usr/local/cuda-12.4


# Install NVIDIA CUDSS
#
RUN curl --location "https://developer.download.nvidia.com/compute/cudss/0.4.0/local_installers/cudss-local-repo-ubuntu2404-0.4.0_0.4.0-1_amd64.deb" --output "cudss-local-repo-u2404.amd.deb"
RUN dpkg --install cudss-local-repo-u2404.amd.deb
RUN cp --archive "/var/cudss-local-repo-ubuntu2404-0.4.0/cudss-local-5A6415D2-keyring.gpg" "/usr/share/keyrings/"
RUN apt-get update
RUN apt-get install cudss
RUN apt-get install libcudss0-cuda-12
RUN apt-get install libcudss0-dev-cuda-12


# Install Intel MKL
#
RUN curl --location --output "GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB" "https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB"
RUN gpg --dearmor --output "/usr/share/keyrings/oneapi-archive-keyring.gpg" "GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB"
RUN echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" > /"etc/apt/sources.list.d/oneAPI.list"
RUN apt-get update
RUN apt-get install intel-oneapi-mkl
RUN apt-get install intel-oneapi-mkl-devel


# Build the ld.so runtime linker cache
#
RUN rm --force "/etc/ld.so.conf.d/"*
RUN echo "/usr/local/cuda-12.4/targets/x86_64-linux/lib" >> "/etc/ld.so.conf.d/toolchain.conf"
RUN ldconfig --verbose


# Install Rust toolchain
#
WORKDIR /workspace/install
RUN curl --location --output rustup-init "https://static.rust-lang.org/rustup/dist/${RUST_ARCH}-unknown-linux-gnu/rustup-init"
RUN chmod +x rustup-init
RUN ./rustup-init -y \
    --profile=minimal \
    --default-host="${RUST_ARCH}-unknown-linux-gnu" \
    --default-toolchain="${RUST_VERSION}-${RUST_ARCH}-unknown-linux-gnu" \
    --target="${RUST_ARCH}-unknown-linux-musl"
RUN cargo install cargo-deb --locked


# Install Golang toolchain
#
RUN curl --location --output "go${GO_VERSION}.linux-amd64.tar.gz" "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
RUN tar --extract --file "go${GO_VERSION}.linux-amd64.tar.gz"
RUN mv go "/usr/local"


# Build python environment
#
WORKDIR "${WORKSPACE_SOURCE_PATH}"
RUN uv venv --python "3.12" --python-preference "only-managed"
