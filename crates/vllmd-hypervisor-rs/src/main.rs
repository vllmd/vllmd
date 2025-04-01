use std::env;
use std::path::Path;
use log::{info, debug};
use anyhow::{Result, Context, bail, anyhow};
use clap::{Command as ClapCommand};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::fs::File;
use signal_hook::iterator::Signals;
use signal_hook::consts::signal::{SIGTERM, SIGINT, SIGHUP};
use std::thread;
// use vmm_sys_util::eventfd::EventFd;
use std::io::Write;
// use std::sync::mpsc::channel;
use termimad;

// Import our hypervisor abstraction
mod hypervisor;
use hypervisor::{HypervisorManager, VmConfig, parse_memory_string};

// Define constants for environment variable names
const LOG_FILEPATH_VAR: &str = "VLLMD_HYPERVISOR_LOG_FILEPATH";
const KERNEL_FILEPATH_VAR: &str = "VLLMD_HYPERVISOR_KERNEL_FILEPATH";
const SYSTEM_IMAGE_FILEPATH_VAR: &str = "VLLMD_HYPERVISOR_SYSTEM_IMAGE_FILEPATH";
const CONFIG_IMAGE_FILEPATH_VAR: &str = "VLLMD_HYPERVISOR_CONFIG_IMAGE_FILEPATH";
const CPU_COUNT_VAR: &str = "VLLMD_HYPERVISOR_CPU_COUNT";
const MEMORY_CONFIG_VAR: &str = "VLLMD_HYPERVISOR_MEMORY_CONFIG";
const DEVICE_FILEPATH_LIST_VAR: &str = "VLLMD_HYPERVISOR_DEVICE_FILEPATH_LIST";
const CMDLINE_VAR: &str = "VLLMD_HYPERVISOR_CMDLINE";
const DEBUG_VAR: &str = "VLLMD_HYPERVISOR_DEBUG";

// Define default values
const DEFAULT_CPU_COUNT: u8 = 4;
const DEFAULT_MEMORY_CONFIG: &str = "size=16G,shared=on";
const DEFAULT_LOG_FILEPATH: &str = "/dev/stdout";

// Define path to store the VM PID for stop command - use XDG runtime dir or fallback to /var/run if available
fn get_pid_file_path() -> String {
    if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
        return format!("{}/vllmd-hypervisor.pid", runtime_dir);
    } else if let Ok(home_dir) = std::env::var("HOME") {
        // Create directory if it doesn't exist
        let run_dir = format!("{}/.local/run/vllmd", home_dir);
        let _ = std::fs::create_dir_all(&run_dir);
        return format!("{}/hypervisor.pid", run_dir);
    } else {
        // Fallback to system runtime directory if accessible
        if std::path::Path::new("/var/run/vllmd").exists() && std::fs::metadata("/var/run/vllmd").map(|m| m.is_dir()).unwrap_or(false) {
            return "/var/run/vllmd/hypervisor.pid".to_string();
        }
        
        // Last resort - this is still not ideal but better than plain /tmp
        "/var/tmp/vllmd-hypervisor.pid".to_string()
    }
}

// Define command verbs
enum CommandVerb {
    Start,
    Stop,
    Status,
    Env,
}

#[derive(Debug)]
struct HypervisorConfig {
    log_filepath: String,
    kernel_filepath: String,
    system_image_filepath: String,
    config_image_filepath: String,
    cpu_count: u8,
    memory_config: String,
    device_filepath_list: Vec<String>,
    cmdline: String,
    debug: bool,
}

impl HypervisorConfig {
    fn from_env() -> Result<Self> {
        // Required variables
        let kernel_filepath = env::var(KERNEL_FILEPATH_VAR)
            .context(format!("Required environment variable {} not set", KERNEL_FILEPATH_VAR))?;
        
        let system_image_filepath = env::var(SYSTEM_IMAGE_FILEPATH_VAR)
            .context(format!("Required environment variable {} not set", SYSTEM_IMAGE_FILEPATH_VAR))?;
        
        let config_image_filepath = env::var(CONFIG_IMAGE_FILEPATH_VAR)
            .context(format!("Required environment variable {} not set", CONFIG_IMAGE_FILEPATH_VAR))?;
        
        // Optional variables with defaults
        let log_filepath = env::var(LOG_FILEPATH_VAR).unwrap_or_else(|_| DEFAULT_LOG_FILEPATH.to_string());
        
        let cpu_count = env::var(CPU_COUNT_VAR)
            .map(|s| s.parse::<u8>().unwrap_or(DEFAULT_CPU_COUNT))
            .unwrap_or(DEFAULT_CPU_COUNT);
        
        let memory_config = env::var(MEMORY_CONFIG_VAR).unwrap_or_else(|_| DEFAULT_MEMORY_CONFIG.to_string());
        
        let device_filepath_list = env::var(DEVICE_FILEPATH_LIST_VAR)
            .map(|s| s.split(',').filter(|s| !s.is_empty()).map(String::from).collect())
            .unwrap_or_else(|_| Vec::new());
        
        let cmdline = env::var(CMDLINE_VAR).unwrap_or_else(|_| String::new());
        
        let debug = env::var(DEBUG_VAR).is_ok();
        
        // Validate paths
        if !Path::new(&kernel_filepath).exists() {
            bail!("Kernel filepath does not exist: {}", kernel_filepath);
        }
        
        if !Path::new(&system_image_filepath).exists() {
            bail!("System image filepath does not exist: {}", system_image_filepath);
        }
        
        if !Path::new(&config_image_filepath).exists() {
            bail!("Config image filepath does not exist: {}", config_image_filepath);
        }
        
        for device_path in &device_filepath_list {
            if !Path::new(device_path).exists() {
                bail!("Device path does not exist: {}", device_path);
            }
        }
        
        Ok(Self {
            log_filepath,
            kernel_filepath,
            system_image_filepath,
            config_image_filepath,
            cpu_count,
            memory_config,
            device_filepath_list,
            cmdline,
            debug,
        })
    }
}

fn setup_logger(log_filepath: &str, debug: bool) -> Result<()> {
    let env = env_logger::Env::default().filter_or("RUST_LOG", if debug { "debug" } else { "info" });
    
    let mut builder = env_logger::Builder::from_env(env);
    
    // Set a colorized format with wide pipe separators
    builder.format(|buf, record| {
        use std::io::Write;
        // Format as YYYYMMDD-HHMMSS
        let timestamp = chrono::Local::now().format("%Y%m%d-%H%M%S");
        
        // Define colors for each field and determine message color based on level
        let level_color = match record.level() {
            log::Level::Error => "\x1B[31m", // Red
            log::Level::Warn => "\x1B[33m",  // Yellow
            log::Level::Info => "\x1B[32m",  // Green
            log::Level::Debug => "\x1B[36m", // Cyan
            log::Level::Trace => "\x1B[35m", // Magenta
        };
        
        // Color the message based on the log level for visual consistency
        // Adding italics (3) and bold (1) formatting
        let message_color = match record.level() {
            log::Level::Error => "\x1B[31;1;3m", // Bold Italic Red
            log::Level::Warn => "\x1B[33;1;3m",  // Bold Italic Yellow
            log::Level::Info => "\x1B[37;1;3m",  // Bold Italic White
            log::Level::Debug => "\x1B[36;1;3m", // Bold Italic Cyan
            log::Level::Trace => "\x1B[35;1;3m", // Bold Italic Magenta
        };
        
        let timestamp_color = "\x1B[34m"; // Blue
        let reset = "\x1B[0m";
        // Double angle brackets (U+00AB, U+00BB) as field delimiters with maximum brightness styling
        let ultra_bright_white = "\x1B[1;38;2;255;255;255m";  // Ultra bright white (bold + 24-bit true color white)
        let left_bracket = "«";  // Left-pointing double angle bracket (U+00AB)
        let right_bracket = "»"; // Right-pointing double angle bracket (U+00BB)
        
        // Use double angle brackets format with simple spacing and bright brackets
        writeln!(
            buf,
            "{}{}{}{}{}{}{}{}  {}{}{}{}{}{}{}{}  {}{}{}{}{}{}{}{}",  // Double angle bracketed format
            ultra_bright_white, left_bracket, reset, 
            timestamp_color, timestamp, 
            ultra_bright_white, right_bracket, reset,
            
            ultra_bright_white, left_bracket, reset,
            level_color, record.level().to_string().to_lowercase(), 
            ultra_bright_white, right_bracket, reset,
            
            ultra_bright_white, left_bracket, reset,
            message_color, record.args(), 
            ultra_bright_white, right_bracket, reset
        )
    });
    
    // Create a dual output logger that writes to both stderr and the specified file
    if log_filepath != "/dev/stdout" {
        // Create a custom logger that writes to both stdout and the file
        struct DualWriter {
            file: File,
            // Static mutex to ensure synchronized writes across all threads
            mutex: std::sync::Mutex<()>,
        }
        
        impl Write for DualWriter {
            fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
                // Lock the mutex for the entire write operation
                let _guard = self.mutex.lock().unwrap();
                
                // Make sure the buffer ends with a newline to prevent incomplete lines
                let buf_to_write = if !buf.ends_with(b"\n") {
                    let mut new_buf = buf.to_vec();
                    new_buf.push(b'\n');
                    new_buf
                } else {
                    buf.to_vec()
                };
                
                // First write to stderr and flush immediately
                std::io::stderr().write_all(&buf_to_write)?;
                std::io::stderr().flush()?;
                
                // Then write to the file and flush immediately
                let result = self.file.write(&buf_to_write);
                self.file.flush()?;
                
                result
            }
            
            fn flush(&mut self) -> std::io::Result<()> {
                let _guard = self.mutex.lock().unwrap();
                std::io::stderr().flush()?;
                self.file.flush()
            }
        }
        
        // Open the log file
        let log_file = File::create(log_filepath)
            .context(format!("Failed to create log file: {}", log_filepath))?;
        
        // Create the dual writer with a mutex
        let dual_writer = DualWriter { 
            file: log_file,
            mutex: std::sync::Mutex::new(()),
        };
        
        // Set up the logger with the dual writer
        builder.target(env_logger::Target::Pipe(Box::new(dual_writer)));
    }
    
    // Initialize the logger
    builder.init();
    
    info!("Logger initialized with level: {}", if debug { "DEBUG" } else { "INFO" });
    Ok(())
}

fn save_vm_pid() -> Result<()> {
    let pid = std::process::id();
    let pid_file = get_pid_file_path();
    info!("Saving VM PID {} to {}", pid, pid_file);
    
    // Ensure parent directory exists
    if let Some(parent) = Path::new(&pid_file).parent() {
        if !parent.exists() {
            std::fs::create_dir_all(parent)
                .context(format!("Failed to create directory: {}", parent.display()))?;
        }
    }
    
    let mut file = File::create(&pid_file)
        .context(format!("Failed to create PID file: {}", pid_file))?;
    
    file.write_all(pid.to_string().as_bytes())
        .context(format!("Failed to write PID to file: {}", pid_file))?;
    
    Ok(())
}

fn get_vm_pid() -> Result<u32> {
    let pid_file = get_pid_file_path();
    if !Path::new(&pid_file).exists() {
        bail!("VM PID file does not exist: {}", pid_file);
    }
    
    let pid_str = std::fs::read_to_string(&pid_file)
        .context(format!("Failed to read PID file: {}", pid_file))?;
    
    pid_str.trim().parse::<u32>().context("Failed to parse PID from file")
}

fn start_hypervisor(config: &HypervisorConfig) -> Result<()> {
    info!("Starting hypervisor with configuration: {:?}", config);
    
    // Create exit signal for clean shutdown
    let exit_signal = Arc::new(AtomicBool::new(false));
    let exit_signal_clone = exit_signal.clone();
    
    // Set up signal handler
    let mut signals = Signals::new(&[SIGTERM, SIGINT, SIGHUP])?;
    let handle = signals.handle();
    
    // Save process ID to file for stop command
    save_vm_pid()?;
    
    thread::spawn(move || {
        for sig in signals.forever() {
            info!("Received signal {:?}", sig);
            exit_signal_clone.store(true, Ordering::SeqCst);
        }
    });
    
    // Create a new hypervisor manager
    let mut hypervisor_manager = HypervisorManager::new()?;
    
    // Parse memory configuration
    let memory_config = parse_memory_string(&config.memory_config)?;
    
    // Generate a UUID for the VM
    let vm_id = uuid::Uuid::new_v4().to_string();
    
    // Create VM configuration
    let vm_config = VmConfig {
        id: vm_id,
        kernel_path: config.kernel_filepath.clone(),
        cmdline: config.cmdline.clone(),
        system_image_path: config.system_image_filepath.clone(),
        config_image_path: config.config_image_filepath.clone(),
        vcpu_count: config.cpu_count,
        memory_config,
        device_paths: config.device_filepath_list.clone(),
        debug: config.debug,
    };
    
    // Configure the hypervisor
    hypervisor_manager.configure(vm_config)?;
    
    // Start the hypervisor
    hypervisor_manager.start()?;
    
    info!("VM started successfully");
    
    // Wait for exit signal
    while !exit_signal.load(Ordering::SeqCst) {
        thread::sleep(std::time::Duration::from_millis(100));
    }
    
    info!("Shutting down VM");
    
    // Shutdown the hypervisor
    hypervisor_manager.shutdown()?;
    
    // Clean up signal handler
    handle.close();
    
    // Remove PID file
    let pid_file = get_pid_file_path();
    if let Err(e) = std::fs::remove_file(&pid_file) {
        debug!("Failed to remove PID file {}: {}", pid_file, e);
    }
    
    info!("VM shutdown complete");
    
    Ok(())
}

fn stop_hypervisor() -> Result<()> {
    info!("Stopping hypervisor");
    
    // Get VM PID
    let pid = match get_vm_pid() {
        Ok(pid) => pid,
        Err(e) => {
            info!("No running hypervisor found: {}", e);
            return Ok(());
        }
    };
    
    info!("Sending SIGTERM to hypervisor process with PID: {}", pid);
    
    // On Unix, we can send a signal to another process
    #[cfg(unix)]
    {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        
        kill(Pid::from_raw(pid as i32), Signal::SIGTERM)
            .map_err(|e| anyhow!("Failed to send SIGTERM to process {}: {}", pid, e))?;
        
        info!("SIGTERM sent successfully");
    }
    
    // On non-Unix platforms, this won't work
    #[cfg(not(unix))]
    {
        info!("Stop command not supported on this platform");
    }
    
    Ok(())
}

fn check_hypervisor_status() -> Result<()> {
    info!("Checking hypervisor status");
    
    // Get VM PID
    let pid = match get_vm_pid() {
        Ok(pid) => pid,
        Err(e) => {
            info!("No running hypervisor found: {}", e);
            println!("Status: Not running");
            return Ok(());
        }
    };
    
    // Check if process is running
    #[cfg(unix)]
    {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        
        match kill(Pid::from_raw(pid as i32), Signal::SIGCONT) {
            Ok(_) => {
                info!("Hypervisor is running with PID: {}", pid);
                println!("Status: Running (PID: {})", pid);
            },
            Err(_) => {
                info!("Hypervisor process with PID {} is not running", pid);
                println!("Status: Not running (stale PID file)");
                
                // Remove stale PID file
                let pid_file = get_pid_file_path();
                if let Err(e) = std::fs::remove_file(&pid_file) {
                    debug!("Failed to remove stale PID file {}: {}", pid_file, e);
                }
            }
        }
    }
    
    // On non-Unix platforms, this won't work
    #[cfg(not(unix))]
    {
        println!("Status: Unknown (status check not supported on this platform)");
    }
    
    Ok(())
}

// Function to show environment variables and their current values
fn create_command_app() -> ClapCommand {
    ClapCommand::new("vllmd-hypervisor")
        .version("0.1.0")
        .author("vllmd-hypervisor")
        .about("VLLMD: Purpose-built hypervisor for secure machine learning inference workloads")
        .subcommand(ClapCommand::new("start").about("Start the hypervisor"))
        .subcommand(ClapCommand::new("stop").about("Stop the hypervisor"))
        .subcommand(ClapCommand::new("status").about("Check hypervisor status"))
        .subcommand(
            ClapCommand::new("env")
                .about("Show environment variables and their values")
                .arg(clap::Arg::new("show-colors")
                    .long("show-colors")
                    .help("Display brand color information")
                    .action(clap::ArgAction::SetTrue))
        )
}

fn show_environment_vars(show_colors: bool) -> Result<()> {
    use termimad::{MadSkin, crossterm::style::Color};
    
    // Convert CPU count to a string first so it lives long enough
    let cpu_count_str = DEFAULT_CPU_COUNT.to_string();
    
    let vars = [
        (LOG_FILEPATH_VAR, Some(DEFAULT_LOG_FILEPATH), "Path where logs will be written"),
        (KERNEL_FILEPATH_VAR, None, "Path to the VM kernel file (required)"),
        (SYSTEM_IMAGE_FILEPATH_VAR, None, "Path to the system disk image (required)"),
        (CONFIG_IMAGE_FILEPATH_VAR, None, "Path to the configuration disk image (required)"),
        (CPU_COUNT_VAR, Some(cpu_count_str.as_str()), "Number of virtual CPUs"),
        (MEMORY_CONFIG_VAR, Some(DEFAULT_MEMORY_CONFIG), "Memory configuration string"),
        (DEVICE_FILEPATH_LIST_VAR, None, "Comma-separated list of device paths to add"),
        (CMDLINE_VAR, None, "Kernel command line parameters"),
        (DEBUG_VAR, None, "Set to any value to enable debug logging"),
    ];
    
    // Build markdown
    let mut markdown = String::from("# Environment Variables for vllmd-hypervisor\n\n");
    markdown.push_str("| Variable Name | Current Value | Description |\n");
    markdown.push_str("|--------------|---------------|-------------|\n");
    
    for (var_name, default, description) in vars.iter() {
        let current_value = match env::var(var_name) {
            // Custom value is bold, but without "_(default)_" text
            Ok(val) => format!("**{}**", val),
            // Default value is bold with "_(default)_" indicator
            Err(_) => match default {
                Some(def) => format!("**{}** _(default)_", def),
                None => "**not set**".to_string(),
            },
        };
        
        markdown.push_str(&format!("| `{}` | {} | `{}` |\n", 
                                 var_name, current_value, description));
    }
    
    markdown.push_str("\n> **Note:** Required variables are marked with `(required)` in the description.\n");
    
    // Apply custom skin with adaptive colors based on terminal preferences
    let mut skin = MadSkin::default();
    
    // Helper function to create RGB colors
    fn rgb(hex: &str) -> Color {
        let r = u8::from_str_radix(&hex[1..3], 16).unwrap_or(255);
        let g = u8::from_str_radix(&hex[3..5], 16).unwrap_or(255);
        let b = u8::from_str_radix(&hex[5..7], 16).unwrap_or(255);
        Color::Rgb { r, g, b }
    }
    
    // Fixed brand colors
    let primary = rgb("#00EA8C");      // Main text color (green)
    let emphasis = rgb("#EA8C00");     // Emphasis/Secondary (orange)
    let accent = rgb("#0ACCF9");       // Accent (blue)
    
    // Simple fixed theme for color display
    
    // Apply colors to skin elements
    skin.paragraph.set_fg(primary);
    skin.bold.set_fg(emphasis);
    skin.italic.set_fg(accent);     // Set description text (italics) to accent color
    skin.inline_code.set_fg(accent);
    skin.headers[0].set_fg(emphasis);
    skin.table.set_fg(primary);
    
    // We'll use the default table border characters
    // as setting custom ones requires a static lifetime
    
    // Add simple brand color example if show_colors is true
    if show_colors {
        let example_string = "Welcome to the vllmd Inferencing Platform.";
        
        markdown.push_str("\n## Brand Colors\n\n");
        markdown.push_str("| Name | Hex Value | Description | Example |\n");
        markdown.push_str("|------|-----------|-------------|--------|\n");
        // Use inline code formatting for description to make it more distinct
        markdown.push_str(&format!("| Primary | #00EA8C | `Vibrant Green` | **{}** |\n", example_string));
        markdown.push_str(&format!("| Accent | #0ACCF9 | `Bright Blue` | **{}** |\n", example_string));
        markdown.push_str(&format!("| Emphasis | #EA8C00 | `Orange` | **{}** |\n", example_string));
    }
    
    // Print the markdown with our custom skin
    skin.print_text(&markdown);
    
    Ok(())
}

fn main() -> Result<()> {
    // Create the command line app
    let app = create_command_app();
    
    // Parse command line arguments
    let matches = app.get_matches();
    
    // Determine command
    let command = if matches.subcommand_matches("start").is_some() {
        CommandVerb::Start
    } else if matches.subcommand_matches("stop").is_some() {
        CommandVerb::Stop
    } else if matches.subcommand_matches("status").is_some() {
        CommandVerb::Status
    } else if matches.subcommand_matches("env").is_some() {
        CommandVerb::Env
    } else {
        // If no subcommand is provided or an invalid one was given, show help message
        let mut app = create_command_app();
        app.print_help()?;
        println!("\n");
        return Ok(());
    };
    
    // Execute command
    match command {
        CommandVerb::Start => {
            // Load configuration from environment
            let config = HypervisorConfig::from_env()?;
            
            // Setup logger
            setup_logger(&config.log_filepath, config.debug)?;
            
            // Start hypervisor
            start_hypervisor(&config)?;
        },
        CommandVerb::Stop => {
            // Setup minimal logging
            env_logger::init();
            
            // Stop hypervisor
            stop_hypervisor()?;
        },
        CommandVerb::Status => {
            // Setup minimal logging
            env_logger::init();
            
            // Check hypervisor status
            check_hypervisor_status()?;
        },
        CommandVerb::Env => {
            // Get any options from the env subcommand
            let env_matches = matches.subcommand_matches("env").unwrap();
            let show_colors = env_matches.get_flag("show-colors");
            
            // Show environment variables
            show_environment_vars(show_colors)?;
        },
    }
    
    Ok(())
}