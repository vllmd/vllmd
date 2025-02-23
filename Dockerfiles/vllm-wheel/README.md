# Component: vllm

A python library for single-node large language model inference with streaming capability, integrated as a component of [the vLLMd platform](https://vllmd.com/).

## Overview

vLLM provides optimized single-node inference for quantized large language models. It excels with batch inference throughput.

Key features:
- **PagedAttention**. Efficient management of attention key and value memory.
- **Continuous Batching**. Dynamic batching of incoming requests on a single server.
- **Accelerated Execution**. Optimized single-node performance with CUDA/HIP graph.
- **Flexible Quantization**. GPTQ, AWQ, INT4, INT8, and FP8 available.

## Architecture

- **Single Node**. Optimized for GPU inference on one node with multiple AI accelerators
- **CUDA kernels**. Typical inferencing operations such as quantization include hand-implemented cuda kernels.
- **Accelerator Memory Management**. The AI accelerator resources are managed for maximum throughput.
- **Batching**. Continuous request batching consumes one or more accelerators on the node.
- **Resource Bounds**. Limited to single node's accelerators memory and compute.

## Hardware Compatibility

Single-node operation on:

NVIDIA accelerators by Compute Capability:
- Compute 7.5 (Turing)
  - [NVIDIA RTX 2080 Ti](https://www.nvidia.com/content/dam/en-zz/Solutions/geforce/news/geforce-rtx-2080-ti-2080-graphics-cards/geforce-rtx-2080-ti-2080-technical-specs.pdf)
  - [NVIDIA T4](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/tesla-t4/t4-tensor-core-datasheet-951643.pdf)
- Compute 8.0 (Ampere)
  - [NVIDIA A10](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a10/nvidia-a10-datasheet.pdf)
  - [NVIDIA A30](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a30/nvidia-a30-datasheet.pdf)
  - [NVIDIA A40](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a40/nvidia-a40-datasheet.pdf)
  - [NVIDIA A100](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a100/pdf/nvidia-a100-datasheet-us-nvidia-1758950-r4-web.pdf)
  - [NVIDIA A800](https://www.nvidia.cn/content/dam/en-zz/Solutions/Data-Center/a800/nvidia-a800-datasheet-2029415.pdf)
- Compute 8.6 (Ampere)
  - [NVIDIA A2](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a2/nvidia-a2-datasheet.pdf)
  - [NVIDIA RTX 3090](https://www.nvidia.com/en-us/geforce/graphics-cards/30-series/rtx-3090-3090ti/)
- Compute 8.9 (Ada Lovelace)
  - [NVIDIA L4](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/l4/nvidia-l4-tensor-core-gpu-datasheet.pdf)
  - [NVIDIA RTX 4090](https://www.nvidia.com/en-us/geforce/graphics-cards/40-series/rtx-4090/)
- Compute 9.0 (Hopper)
  - [NVIDIA H100](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/h100/h100-tensor-core-gpu-datasheet.pdf)
  - [NVIDIA H800](https://www.nvidia.cn/content/dam/en-zz/Solutions/Data-Center/h800/nvidia-h800-datasheet-2029415.pdf)

Other Hardware:
- AMD CPUs + accelerators
- Intel CPUs + accelerators
- PowerPC CPUs
- TPU
- AWS Neuron

## Key Capabilities

- High throughput on a single node
- Integration with Hugging Face and ModelScope models
- Multiple model file format decoding
- Single-node tensor and pipeline parallelism
- Streaming output
- Prefix caching
- Multi-LoRA capabilities

## Compatible Models

Available for popular open-source models within single-node memory constraints:
- Transformer-based LLMs (e.g., Llama)
- Mixture-of-Expert LLMs (e.g., Mixtral)
- Embedding Models (e.g., E5-Mistral)
- Multi-modal LLMs (e.g., LLaVA)

## Installation

Using uv:
```bash
uv pip install vllm
```

To build from source, visit the [reference wheel build script](https://vllmd.com/architecture/components/vllm/build/Dockerfile).

## Usage

Basic example of model loading and inference on a single node:

```python
from vllm import LLM

# Initialize the model on local hardware
llm = LLM(model="meta-llama/Llama-2-7b-chat-hf")

# Generate text using local resources
output = llm.generate("Tell me a short story.")
```

## License

This component is licensed with the same terms as the original vLLM project.
For dtailed licensing information, visit [https://vllmd.com/architecture/components/vllm/LICENSE](https://vllmd.com/architecture/components/vllm/LICENSE)

## Documentation

For documentation of this component visit [https://vllmd.com/architecture/components/vllm/usage](https://vllmd.com/architecture/components/vllm/usage)
