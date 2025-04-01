# VLLMD: Enterprise Inference Platform

`VLLMD` delivers reliable enterprise machine learning inference with comprehensive boundary
protection while delivering an exceptional operational experience.

## Our Mission

Enable enterprises to adopt machine learning inferencing in production environments.

## Our Philosophy

- **Security First**.
- **Reliability First**.
- **Usability First**.

## Core Components

### vllmd-hypervisor

The `vllmd-hypervisor` manages the virtualization component with these capabilities:

- Metal-level performance with hardware accelerator isolation.
- Automated network configuration.
- Authentication, authorization, and auditing occur on each boundary.

- Take a look at  the code -> [vllmd-hypervisor-rs](crates/vllmd-hypervisor-rs/README.md).

### vllmd-runtime-assembler

The `vllmd-runtime-assembler` creates production-ready virtualized runtimes that contain:

- `Debian` optimized for machine learning workloads.
- `NVIDIA` driver integration with direct hardware access.
- `Containerd` runtime with Accelerator extensions.
- `vLLM` (`Very Large Language Model`) inference engine.
- Zero-configuration `Kubernetes` node components.
- `Systemd` service management.

### vllmd-runtime-node

The `vllmd-runtime-node` delivers inference capabilities on a single node:

- Batteries included machine learning inference environment ready for production.
- Pre-optimized configuration for specific hardware profiles.
- Automatic resource detection and utilization.
- Built-in monitoring and diagnostics.

### vllmd-runtime-controller

The `vllmd-runtime-controller` assembles the control plane:

- Control plane orchestration across `Kubernetes` nodes.
- Component bootstrapping with dependency management.
- Health monitoring with automated recovery.
- Updates management with zero downtime operation.

### vllmd-control-plane-controller

The `vllmd-control-plane-controller` controls `Kubernetes`:

- Dynamic certificate management and rotation.
- Self-discovery and assembly node registration with verification.
- Resource-aware scheduling with hardware affinity.

## Getting Started

### Quick Start

Initialize your environment:

```bash
vllmdctl initialize environment
```

Create a `runtime.yaml`:

```yaml
apiVersion: vllmd.com/v1alpha1
kind: Runtime
metadata:
  name: r1-qwen32b-int8
spec:
  model:
    name: r1-qwen32b-int8
    source: huggingface
    repository: vllmd/deepseek-r1-distill-qwen-32b-w8a8-dynamic
  resources:
    accelerator_memory: 48Gi
    accelerator_count: 1
    accelerator_type: nvidia-a40
  scaling:
    minReplicas: 1
    maxReplicas: 3
```

Deploy your first model:

```bash
vllmdctl apply runtime.yaml
```

Access model through the API

```bash
vllmdctl infer "Explain why PI is so awesome."
```

### Production Setup

```bash
# Verify hardware compatibility and IOMMU configuration
vllmdctl runtimes precheck

# Configure the runtimes to split available cpus, memory, and accelerators.
vllmdctl runtimes configure --cpu split --memory split --accelerators split

# Generate optimized runtime image
vllmdctl runtimes generate

# Launch runtime by identity. This allocates resources to the runtime.
vllmdctl runtimes start runtime_id
```

## Security `not` through obscurity

`VLLMD` isolates components. Isolation enables you to validate the components on their respective
boundaries.

You use authentication to assign an identity to a request. You then use authorization to accept or
deny a request based upon the identity you authenticated. Finally, you audit the request by storing
the requests in a tamper-proof system log. This combined set of techniques is commonly referred to
within industry as `AAA`.

By isolating every component, you can then validate on every component's boundary that the request's
identity is entitled to access a resource.

1. **Compute Isolation**. Hardware-level virtualization creates separate execution environments with
   dedicated `CPU` and memory resources, preventing cross-workload interference.
1. **Accelerator Isolation**. `IOMMU`-based `Accelerator` virtualization enables direct hardware
   access while maintaining strict boundaries between workloads, ensuring one model cannot access
   another's `Accelerator` memory.
1. **Network Isolation**. Multi-tenant network configuration with dedicated virtual interfaces and
   security policies prevents unauthorized communication between workloads.
1. **Identity Boundary Isolation**. Verification at each security boundary ensures only authorized
   entities can communicate across isolation boundaries, preventing credential or token leakage.

You use some other techniques to further amplify the security of the system.

- **Multi-Factor Identity Verification**: Every user, service and process proves who they are.
- **Granular Access Controls**: Pre-configured roles with specific permissions similar to
  `Kubernetes` RBAC.
- **Complete Audit Trails**: Every action is logged with source, target, and context.

These different components communicate with one-another using a network. The network connects each
component in a fully-meshed network structure. The different components do not trust any other
components. And that is key, as that is what ensures the security of this architecture. This
architecture is commonly referred to as `zero-trust` architecture.

If these components have zero trust in other components how could they possibly trust the
communication from other components? Each component has a cryptographic identity with a certificate
issued by a trusted Certificate Authority. The component generates its own private key and the CA
only signs the public key portion. The private key is never shared with anyone, including the CA.

When `vllmd-runtime-one` sends a message to `vllmd-runtime-two`, the process works as follows:

1. `vllmd-runtime-one` digitally signs the message using its private key.
1. `vlmd-runtime-one` encrypts the message using `vllmd-runtime-two`'s public key.
1. `vllmd-runtime-one` stores its pesonal identity in the message.
1. `vllmd-runtime-one` stores the destination identit y in the messsge.
1. The encrypted and signed message is then transmitted across the network.
1. `vllmd-runtime-two` receives the message and verifies the sender's identity.
1. Identity is verified by checking `vllmd-runtime-one`'s public key.
1. `vllmd-runtime-two` decrypts the message using its own private key.

THe example shows that `vllmd-runtime-two` was able to verify the identity of the sender.

The `zero-trust` buzzword is a bit of a misnomer. In reality, each component trusts itself. And this
approach means total and absolute security for your teams.

## How You Deliver Security

Instead of relying on buzzwords, you use `VLLMD` to implement specific security principles that
provide robust protection:

- **Assume Breach Mindset**. Security controls designed assuming attackers may already be present.
- **End-to-End Encryption**. All data protected in transit between system components.
- **End-to-End Identity**. Every communication has a source and destination identity.

This enables continuous verification. Every access request is fully authenticated and authorized regardless of source. These concrete practices create a security-first architecture that protects your machine learning inference workloads and data at every component boundary.
