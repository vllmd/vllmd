# Set up environment variables
cargo build --release
export VLLMD_HYPERVISOR_KERNEL_FILEPATH="/var/lib/artificial_wisdom/hypervisor-fw"
export VLLMD_HYPERVISOR_SYSTEM_IMAGE_FILEPATH="$HOME/vllmd-hypervisor-runtime.raw"
export VLLMD_HYPERVISOR_CONFIG_IMAGE_FILEPATH="/mnt/aw/cloudinit-boot-disk.raw"
export VLLMD_HYPERVISOR_CPU_COUNT="4"
export VLLMD_HYPERVISOR_MEMORY_CONFIG="size=64G"
export VLLMD_HYPERVISOR_CMDLINE="console=hvc0"
export VLLMD_HYPERVISOR_DEVICE_FILEPATH_LIST="/sys/bus/pci/devices/0000:01:00.0"
export VLLMD_HYPERVISOR_LOG_FILEPATH="$HOME/ch-log.txt"
export VLLMD_HYPERVISOR_DEBUG=1
./target/release/vllmd-hypervisor start
