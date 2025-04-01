use anyhow::{Result, anyhow, Context};
use log::{info, warn, error};
use std::path::Path;
use thiserror::Error;
use vmm_sys_util::eventfd::EventFd;
use std::sync::Arc;

// Cloud Hypervisor crates
use hypervisor as ch_hypervisor;
use hypervisor::Hypervisor as ChHypervisor;
use vmm::api::{ApiRequest, VmCreate, VmBoot, VmShutdown, VmInfo, ApiAction};
use vmm::config::VmParams;
use vmm::vm_config::VmConfig as ChVmConfig;
use vmm::VmmVersionInfo;
use vmm::VmmThreadHandle;
use seccompiler::SeccompAction;
use std::sync::mpsc::{channel, Sender};

/// Error type for hypervisor operations
#[derive(Error, Debug)]
pub enum HypervisorError {
    #[error("Failed to start VM: {0}")]
    StartError(String),
    
    #[error("Failed to configure VM: {0}")]
    ConfigError(String),
    
    #[error("Failed to shutdown VM: {0}")]
    ShutdownError(String),
    
    #[error("Invalid VM state: {0}")]
    InvalidState(String),
    
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
    
    #[error("VM parsing error: {0}")]
    ParsingError(String),
    
    #[error("Hypervisor error: {0}")]
    HypervisorError(String),
    
    #[error("API communication error: {0}")]
    ApiError(String),
}

/// Configuration for a virtual machine
#[derive(Debug, Clone)]
pub struct VmConfig {
    /// UUID of the VM
    pub id: String,
    
    /// Path to kernel
    pub kernel_path: String,
    
    /// Kernel command line
    pub cmdline: String,
    
    /// Path to system image
    pub system_image_path: String,
    
    /// Path to config image
    pub config_image_path: String,
    
    /// Number of vCPUs
    pub vcpu_count: u8,
    
    /// Memory configuration
    pub memory_config: MemoryConfig,
    
    /// Devices to passthrough
    pub device_paths: Vec<String>,
    
    /// Debug mode
    pub debug: bool,
}

/// State of a virtual machine
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VmState {
    Created,
    Configured,
    Running,
    Paused,
    Shutdown,
    Error,
}

/// Struct representing the hypervisor manager
pub struct HypervisorManager {
    /// VM state
    state: VmState,
    
    /// VM configuration
    config: Option<VmConfig>,
    
    /// Exit event
    exit_evt: EventFd,
    
    /// API event
    api_evt: EventFd,
    
    /// API sender
    api_sender: Sender<ApiRequest>,
    
    /// VMM thread handle
    vmm_thread_handle: Option<VmmThreadHandle>,
    
    /// Cloud Hypervisor instance
    hypervisor: Option<Arc<dyn ChHypervisor>>,
    
    /// Whether the VM was successfully created
    vm_created: bool,
    
    /// Whether the VM was successfully booted
    vm_booted: bool,
}

impl HypervisorManager {
    /// Create a new hypervisor manager
    pub fn new() -> Result<Self> {
        // Create event fds for API and exit
        let api_evt = EventFd::new(libc::EFD_NONBLOCK)
            .map_err(|e| anyhow!("Failed to create API EventFd: {}", e))?;
        
        let exit_evt = EventFd::new(libc::EFD_NONBLOCK)
            .map_err(|e| anyhow!("Failed to create exit EventFd: {}", e))?;
        
        // Create channel for API requests
        let (api_sender, _) = channel();
        
        Ok(Self {
            state: VmState::Created,
            config: None,
            exit_evt,
            api_evt,
            api_sender,
            vmm_thread_handle: None,
            hypervisor: None,
            vm_created: false,
            vm_booted: false,
        })
    }
    
    /// Configure the hypervisor with the provided configuration
    pub fn configure(&mut self, config: VmConfig) -> Result<()> {
        // Validate VM is in the correct state
        if self.state != VmState::Created {
            return Err(anyhow!(HypervisorError::InvalidState(
                format!("VM must be in Created state to configure, current state: {:?}", self.state)
            )));
        }
        
        // Validate configuration
        self.validate_config(&config)?;
        
        // Store configuration
        self.config = Some(config);
        self.state = VmState::Configured;
        
        info!("Hypervisor configured successfully");
        Ok(())
    }
    
    /// Validate VM configuration
    fn validate_config(&self, config: &VmConfig) -> Result<()> {
        // Validate kernel path
        if !Path::new(&config.kernel_path).exists() {
            return Err(anyhow!(HypervisorError::ConfigError(
                format!("Kernel path does not exist: {}", config.kernel_path)
            )));
        }
        
        // Validate system image path
        if !Path::new(&config.system_image_path).exists() {
            return Err(anyhow!(HypervisorError::ConfigError(
                format!("System image path does not exist: {}", config.system_image_path)
            )));
        }
        
        // Validate config image path
        if !Path::new(&config.config_image_path).exists() {
            return Err(anyhow!(HypervisorError::ConfigError(
                format!("Config image path does not exist: {}", config.config_image_path)
            )));
        }
        
        // Validate device paths
        for device_path in &config.device_paths {
            if !Path::new(device_path).exists() {
                return Err(anyhow!(HypervisorError::ConfigError(
                    format!("Device path does not exist: {}", device_path)
                )));
            }
        }
        
        Ok(())
    }
    
    /// Convert our VmConfig to Cloud Hypervisor's VmParams
    fn create_vm_params(&self) -> Result<VmParams<'static>> {
        // Get config
        let config = self.config.as_ref()
            .ok_or_else(|| anyhow!(HypervisorError::InvalidState("VM not configured".to_string())))?;
        
        // Create string arguments for Cloud Hypervisor
        let cpus = format!("boot={},max={}", config.vcpu_count, config.vcpu_count);
        
        // Create memory configuration
        let memory = if config.memory_config.shared {
            format!("size={}M,shared=on", config.memory_config.size / (1024 * 1024))
        } else {
            format!("size={}M", config.memory_config.size / (1024 * 1024))
        };
        
        // Kernel and cmdline
        let kernel = config.kernel_path.clone();
        let cmdline = config.cmdline.clone();
        
        // Create disk arguments
        let mut disks = Vec::new();
        disks.push(format!("path={},id=system", config.system_image_path));
        disks.push(format!("path={},readonly=on,id=config", config.config_image_path));
        
        // Convert disks to Vec<&'static str>
        let disks_option: Option<Vec<&'static str>> = if !disks.is_empty() {
            // Leak the strings so they have static lifetimes
            let leaked_disks: Vec<&'static str> = disks
                .iter()
                .map(|s| {
                    let leaked: &'static str = Box::leak(s.clone().into_boxed_str());
                    leaked
                })
                .collect();
            Some(leaked_disks)
        } else {
            None
        };
        
        // Create device arguments
        let devices_option: Option<Vec<&'static str>> = if !config.device_paths.is_empty() {
            let devices: Vec<String> = config.device_paths.iter()
                .enumerate()
                .map(|(i, path)| format!("path={},id=dev{}", path, i))
                .collect();
            
            // Leak the strings so they have static lifetimes
            let leaked_devices: Vec<&'static str> = devices
                .iter()
                .map(|s| {
                    let leaked: &'static str = Box::leak(s.clone().into_boxed_str());
                    leaked
                })
                .collect();
            Some(leaked_devices)
        } else {
            None
        };
        
        // Leak strings for static lifetime
        let cpus_static: &'static str = Box::leak(cpus.into_boxed_str());
        let memory_static: &'static str = Box::leak(memory.into_boxed_str());
        let kernel_static = Some(Box::leak(kernel.into_boxed_str()) as &'static str);
        let cmdline_static = if cmdline.is_empty() { 
            None 
        } else { 
            Some(Box::leak(cmdline.into_boxed_str()) as &'static str) 
        };
        
        // Create standard parameters
        let params = VmParams {
            cpus: cpus_static,
            memory: memory_static,
            memory_zones: None,
            firmware: None,
            kernel: kernel_static,
            initramfs: None,
            cmdline: cmdline_static,
            rate_limit_groups: None,
            disks: disks_option,
            net: None,
            rng: "src=/dev/urandom",
            balloon: None,
            fs: None,
            pmem: None,
            serial: "null",
            console: "tty",
            #[cfg(target_arch = "x86_64")]
            debug_console: "off",
            devices: devices_option,
            user_devices: None,
            vdpa: None,
            vsock: None,
            pvpanic: false,
            #[cfg(target_arch = "x86_64")]
            sgx_epc: None,
            numa: None,
            watchdog: false,
            #[cfg(feature = "guest_debug")]
            gdb: false,
            pci_segments: None,
            platform: None,
            tpm: None,
            landlock_enable: false,
            landlock_rules: None,
        };
        
        Ok(params)
    }
    
    /// Start the hypervisor
    pub fn start(&mut self) -> Result<()> {
        // Validate VM is in the correct state
        if self.state != VmState::Configured {
            return Err(anyhow!(HypervisorError::InvalidState(
                format!("VM must be in Configured state to start, current state: {:?}", self.state)
            )));
        }
        
        // Create VM parameters
        let vm_params = self.create_vm_params()?;
        
        // Parse VM parameters into VM config
        let ch_vm_config = ChVmConfig::parse(vm_params)
            .map_err(|e| HypervisorError::ParsingError(format!("{:?}", e)))?;
        
        // Create and setup hypervisor
        info!("Initializing hypervisor");
        let hypervisor = ch_hypervisor::new()
            .map_err(|e| HypervisorError::HypervisorError(format!("{:?}", e)))?;
        
        // Clone event FDs
        let api_evt_clone = self.api_evt.try_clone()
            .map_err(|e| HypervisorError::IoError(e))?;
        
        let _exit_evt_clone = self.exit_evt.try_clone()
            .map_err(|e| HypervisorError::IoError(e))?;
        
        // Setup seccomp
        let seccomp_action = SeccompAction::Allow;
        
        // Build the VMM version info
        let vmm_version = VmmVersionInfo::new(
            env!("CARGO_PKG_VERSION"),
            env!("CARGO_PKG_VERSION")
        );
        
        // Start VMM thread
        let vmm_thread_handle = vmm::start_vmm_thread(
            vmm_version,
            &None, // No API socket path
            None,  // No API socket fd
            self.api_evt.try_clone()
                .map_err(|e| HypervisorError::IoError(e))?, // API event
            self.api_sender.clone(), // API sender
            channel().1, // API receiver (we created our own)
            #[cfg(feature = "guest_debug")]
            None, // No GDB socket path
            #[cfg(feature = "guest_debug")]
            EventFd::new(libc::EFD_NONBLOCK).unwrap(), // Debug event
            #[cfg(feature = "guest_debug")]
            EventFd::new(libc::EFD_NONBLOCK).unwrap(), // VM debug event
            self.exit_evt.try_clone()
                .map_err(|e| HypervisorError::IoError(e))?, // exit event
            &seccomp_action,
            hypervisor,
            false, // No landlock
        )
        .map_err(|e| HypervisorError::StartError(format!("{:?}", e)))?;
        
        // Store hypervisor
        self.vmm_thread_handle = Some(vmm_thread_handle);
        
        // Create the VM
        info!("Creating VM");
        let vm_create_result = VmCreate.send(
            api_evt_clone.try_clone().unwrap(), 
            self.api_sender.clone(), 
            Box::new(ch_vm_config)
        );
        
        match vm_create_result {
            Ok(_) => {
                info!("VM created successfully");
                self.vm_created = true;
            },
            Err(e) => {
                return Err(anyhow!(HypervisorError::ApiError(
                    format!("Failed to create VM: {:?}", e)
                )));
            }
        }
        
        // Boot the VM
        info!("Booting VM");
        let vm_boot_result = VmBoot.send(api_evt_clone, self.api_sender.clone(), ());
        
        match vm_boot_result {
            Ok(_) => {
                info!("VM booted successfully");
                self.vm_booted = true;
                self.state = VmState::Running;
            },
            Err(e) => {
                return Err(anyhow!(HypervisorError::ApiError(
                    format!("Failed to boot VM: {:?}", e)
                )));
            }
        }
        
        info!("VM started successfully");
        Ok(())
    }
    
    /// Shutdown the hypervisor
    pub fn shutdown(&mut self) -> Result<()> {
        // Check if a VM is running
        if self.state != VmState::Running && self.state != VmState::Paused {
            info!("No running VM to shut down");
            return Ok(());
        }
        
        if self.vmm_thread_handle.is_some() {
            info!("Shutting down VM");
            
            // Clone event FD
            let api_evt_clone = self.api_evt.try_clone()
                .map_err(|e| HypervisorError::IoError(e))?;
            
            if self.vm_booted {
                // Try to use the API to shutdown the VM gracefully
                let shutdown_result = VmShutdown.send(api_evt_clone, self.api_sender.clone(), ());
                
                match shutdown_result {
                    Ok(_) => {
                        info!("VM shutdown command sent successfully");
                    },
                    Err(e) => {
                        warn!("Failed to send VM shutdown command: {:?}", e);
                    }
                }
            }
            
            // Signal exit to force shutdown if needed
            info!("Triggering exit event");
            if let Err(e) = self.exit_evt.write(1) {
                warn!("Failed to trigger exit event: {}", e);
            }
            
            // Wait for VMM thread to finish
            if let Some(handle) = self.vmm_thread_handle.take() {
                if let Err(e) = handle.thread_handle.join() {
                    error!("Failed to join VMM thread: {:?}", e);
                }
                
                // Clean up HTTP API if it exists
                if let Some(api_handle) = handle.http_api_handle {
                    if let Err(e) = vmm::api::http::http_api_graceful_shutdown(api_handle) {
                        error!("Failed to shutdown HTTP API: {:?}", e);
                    }
                }
            }
        }
        
        // Update state
        self.state = VmState::Shutdown;
        self.vm_created = false;
        self.vm_booted = false;
        
        info!("VM shutdown complete");
        Ok(())
    }
    
    /// Check if the hypervisor is running
    pub fn is_running(&self) -> bool {
        self.state == VmState::Running
    }
    
    /// Get the current state of the hypervisor
    pub fn state(&self) -> VmState {
        self.state
    }
    
    /// Get the VM info
    pub fn info(&self) -> Result<String> {
        if self.state != VmState::Running {
            return Err(anyhow!(HypervisorError::InvalidState(
                format!("VM must be in Running state to get info, current state: {:?}", self.state)
            )));
        }
        
        // Clone event FD
        let api_evt_clone = self.api_evt.try_clone()
            .map_err(|e| HypervisorError::IoError(e))?;
        
        // Send info request
        let info_result = VmInfo.send(api_evt_clone, self.api_sender.clone(), ());
        
        match info_result {
            Ok(_response) => {
                // In a real implementation, we would parse the VM info
                // For now, just return a generic message
                Ok(format!("VM is running (state: active)"))
            },
            Err(e) => {
                Err(anyhow!(HypervisorError::ApiError(
                    format!("Failed to get VM info: {:?}", e)
                )))
            }
        }
    }
}

/// Create a new hypervisor instance
pub fn new() -> Result<Arc<dyn ChHypervisor>> {
    ch_hypervisor::new()
        .map_err(|e| anyhow!("Failed to create hypervisor: {:?}", e))
}

/// Parse a memory configuration string
pub fn parse_memory_string(memory_config: &str) -> Result<MemoryConfig> {
    // Parse a string like "size=16G,shared=on"
    let mut config = MemoryConfig {
        size: 16 * 1024 * 1024 * 1024, // Default 16G
        shared: false,
        hugepages: false,
        shared_memory_size: None,
    };
    
    for part in memory_config.split(',') {
        let kv: Vec<&str> = part.splitn(2, '=').collect();
        if kv.len() != 2 {
            return Err(anyhow!("Invalid memory configuration format: {}", part));
        }
        
        match kv[0].trim() {
            "size" => {
                let size_str = kv[1].trim();
                let multiplier = match size_str.chars().last() {
                    Some('K') | Some('k') => 1024,
                    Some('M') | Some('m') => 1024 * 1024,
                    Some('G') | Some('g') => 1024 * 1024 * 1024,
                    Some('T') | Some('t') => 1024 * 1024 * 1024 * 1024,
                    Some(c) if c.is_digit(10) => 1,
                    _ => return Err(anyhow!("Invalid size unit in memory configuration: {}", size_str)),
                };
                
                let size_num = if size_str.chars().last().unwrap().is_alphabetic() {
                    size_str[..size_str.len()-1].parse::<u64>()
                        .context(format!("Failed to parse memory size: {}", size_str))?
                } else {
                    size_str.parse::<u64>()
                        .context(format!("Failed to parse memory size: {}", size_str))?
                };
                
                config.size = size_num * multiplier;
            },
            "shared" => {
                match kv[1].trim() {
                    "on" | "true" | "yes" | "1" => config.shared = true,
                    "off" | "false" | "no" | "0" => config.shared = false,
                    _ => return Err(anyhow!("Invalid shared value in memory configuration: {}", kv[1])),
                }
            },
            "hugepages" => {
                match kv[1].trim() {
                    "on" | "true" | "yes" | "1" => config.hugepages = true,
                    "off" | "false" | "no" | "0" => config.hugepages = false,
                    _ => return Err(anyhow!("Invalid hugepages value in memory configuration: {}", kv[1])),
                }
            },
            _ => {
                warn!("Unknown memory configuration option: {}", kv[0]);
            }
        }
    }
    
    Ok(config)
}

/// Configuration for VM memory
#[derive(Debug, Clone)]
pub struct MemoryConfig {
    /// Memory size in bytes
    pub size: u64,
    
    /// Whether to use shared memory
    pub shared: bool,
    
    /// Whether to use hugepages
    pub hugepages: bool,
    
    /// Size of shared memory region (if used)
    pub shared_memory_size: Option<u64>,
}