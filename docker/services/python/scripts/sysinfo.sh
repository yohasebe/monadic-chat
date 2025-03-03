#!/bin/bash

# Set error handling

set -uo pipefail

# Function to check if command exists and is executable

command_exists() {
    command -v "$1" >/dev/null 2>&1 && [ -x "$(command -v "$1")" ]
}

# Function to check if running in Docker

is_in_docker() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Function to detect OS

get_os_type() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

# Function to get detailed architecture information

get_detailed_arch() {
    local arch
    arch=$(uname -m)
    
    # Check for container runtime constraints

    if [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
        echo "Container CPU Quota: $(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)"
        echo "Container CPU Period: $(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)"
    fi
    
    # Check for hardware capabilities

    if [ -f /proc/cpuinfo ]; then
        if grep -q "flags" /proc/cpuinfo; then
            echo "CPU Capabilities:"
            grep "flags" /proc/cpuinfo | head -n1 | cut -d':' -f2
        fi
    fi
    
    # Check for virtualization

    if command_exists systemd-detect-virt; then
        echo "Virtualization: $(systemd-detect-virt 2>/dev/null || echo 'none')"
    fi
    
    # Check for container technology

    if [ -f /.dockerenv ]; then
        echo "Container Type: Docker"
    elif [ -f /run/.containerenv ]; then
        echo "Container Type: Podman/OCI"
    fi
}

# Function to get CPU architecture information

get_cpu_arch() {
    echo "CPU Architecture Information:"
    echo "----------------"
    
    local os_type
    os_type=$(get_os_type)
    
    # Get basic architecture

    local arch
    arch=$(uname -m)
    echo "Architecture: $arch"
    
    # Get more detailed CPU information

    case "$os_type" in
        "linux")
            if [ -f /proc/cpuinfo ]; then
                echo -e "\nDetailed CPU Information:"
                
                # Get vendor

                if grep -q "vendor_id" /proc/cpuinfo; then
                    echo "Vendor: $(grep "vendor_id" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -d ' ')"
                fi
                
                # Get model name

                if grep -q "model name" /proc/cpuinfo; then
                    echo "Model: $(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -d ' ')"
                fi
                
                # Check if it's ARM

                if grep -q "CPU architecture" /proc/cpuinfo; then
                    echo "ARM Architecture: $(grep "CPU architecture" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -d ' ')"
                    if grep -q "CPU variant" /proc/cpuinfo; then
                        echo "ARM Variant: $(grep "CPU variant" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -d ' ')"
                    fi
                    if grep -q "CPU implementer" /proc/cpuinfo; then
                        echo "ARM Implementer: $(grep "CPU implementer" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -d ' ')"
                    fi
                fi
                
                # Get number of cores (consider cgroup limitations)

                if [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
                    local quota period
                    quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
                    period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
                    if [ "$quota" -gt 0 ]; then
                        echo "Container CPU Limit: $((quota / period)) cores"
                    fi
                fi
                echo "Total CPU Cores: $(grep -c "processor" /proc/cpuinfo)"
                
                # Get CPU Features

                if grep -q "flags" /proc/cpuinfo; then
                    echo -e "\nCPU Features:"
                    echo "$(grep "flags" /proc/cpuinfo | head -n1 | cut -d':' -f2)"
                elif grep -q "Features" /proc/cpuinfo; then
                    echo -e "\nARM CPU Features:"
                    echo "$(grep "Features" /proc/cpuinfo | head -n1 | cut -d':' -f2)"
                fi
            fi
            
            # Try to get additional CPU capabilities

            if command_exists lscpu; then
                echo -e "\nCPU Capabilities (lscpu):"
                lscpu | grep -E "Architecture|Byte Order|CPU op-mode|Thread|Core|Socket|Vendor|Model|Stepping|BogoMIPS|Virtualization|Cache"
            fi
            ;;
            
        "macos")
            echo -e "\nDetailed CPU Information:"
            
            # Get CPU brand

            if command_exists sysctl; then
                # Get CPU brand string

                sysctl -n machdep.cpu.brand_string 2>/dev/null
                
                # Get more CPU details

                echo -e "\nCPU Details:"
                echo "Cores: $(sysctl -n hw.ncpu 2>/dev/null)"
                echo "Physical Cores: $(sysctl -n hw.physicalcpu 2>/dev/null)"
                echo "Logical Cores: $(sysctl -n hw.logicalcpu 2>/dev/null)"
                
                # Check if ARM (Apple Silicon) or Intel

                if [ "$arch" = "arm64" ]; then
                    echo "Processor Type: Apple Silicon"
                    # Try to get more Apple Silicon specific info

                    system_profiler SPHardwareDataType 2>/dev/null | grep "Chip"
                else
                    echo "Processor Type: Intel"
                    # Get Intel specific features

                    echo -e "\nCPU Features:"
                    sysctl -n machdep.cpu.features 2>/dev/null
                    sysctl -n machdep.cpu.leaf7_features 2>/dev/null
                fi
            fi
            ;;
            
        *)
            echo "Detailed CPU information not available for this OS"
            ;;
    esac
    echo
}

# Function to read proc stat and calculate CPU usage

get_proc_cpu_usage() {
    if [ -f /proc/stat ]; then
        local cpu_line
        cpu_line=$(head -n1 /proc/stat)
        # Extract CPU times

        local user system idle
        read -r _ user _ system _ _ _ _ idle _ < <(echo "$cpu_line")
        local total=$((user + system + idle))
        local usage=$((100 * (user + system) / total))
        echo "CPU Usage (calculated from /proc/stat): ~${usage}%"
        return 0
    fi
    return 1
}

# Function to get CPU usage

get_cpu_usage() {
    echo "CPU Usage:"
    echo "----------------"
    
    local os_type
    os_type=$(get_os_type)
    
    if [ "$os_type" = "linux" ]; then
        if command_exists top; then
            top -bn1 | grep "Cpu(s)" || get_proc_cpu_usage || echo "Could not get CPU usage"
        else
            get_proc_cpu_usage || echo "Could not get CPU usage"
        fi
    elif [ "$os_type" = "macos" ]; then
        if command_exists top; then
            top -l 1 | grep "CPU usage" || echo "Could not get CPU usage"
        fi
    fi
    echo
}

# Function to get GPU information

get_gpu_info() {
    echo "GPU Information:"
    echo "----------------"
    
    if is_in_docker; then
        echo "Running in Docker container"
        
        # Check for NVIDIA Container Toolkit

        if [ -e /dev/nvidia0 ] || [ -e /dev/nvidiactl ]; then
            echo "NVIDIA GPU detected (Container Toolkit enabled)"
            if command_exists nvidia-smi; then
                echo "NVIDIA SMI information:"
                nvidia-smi -q --display=COMPUTE,MEMORY,POWER
            fi
        fi
        
        # Check for Intel GPU

        if [ -e /dev/dri ]; then
            echo "Intel/AMD GPU devices:"
            ls -l /dev/dri/
            if command_exists intel_gpu_top; then
                intel_gpu_top -J
            fi
        fi
        
        # Check for ROCm

        if [ -e /dev/kfd ] || [ -e /dev/dri/renderD128 ]; then
            echo "AMD GPU detected"
            if command_exists rocm-smi; then
                rocm-smi
            fi
        fi
    else
        # Non-container GPU detection

        if command_exists nvidia-smi; then
            echo "NVIDIA GPU information:"
            nvidia-smi
        elif [ -d /sys/class/drm ]; then
            echo "GPU devices found in /sys/class/drm:"
            for card in /sys/class/drm/card[0-9]*; do
                if [ -f "$card/device/vendor" ]; then
                    vendor=$(cat "$card/device/vendor" 2>/dev/null)
                    device=$(cat "$card/device/device" 2>/dev/null)
                    echo "GPU Device: $card"
                    echo "  Vendor ID: $vendor"
                    echo "  Device ID: $device"
                fi
            done
        fi
    fi
    echo
}

# Function to show help message

show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -c, --cpu       Show CPU usage"
    echo "  --cpu-arch      Show detailed CPU architecture information"
    echo "  -g, --gpu       Show GPU information"
    echo "  --all           Show all information (default)"
    echo "  -h, --help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0              # Show all information"
    echo "  $0 -c          # Show CPU usage"
    echo "  $0 --cpu-arch   # Show detailed CPU architecture information"
    echo
}

# Main function

main() {
    local show_all=false
    local show_cpu=true
    local show_cpu_arch=true
    local show_gpu=true

    # Process command line arguments

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cpu)
                show_cpu=true
                show_all=false
                shift
                ;;
            --cpu-arch)
                show_cpu_arch=true
                show_all=false
                shift
                ;;
            -g|--gpu)
                show_gpu=true
                show_all=false
                shift
                ;;
            --all)
                show_all=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Show system information

    echo "=== System Information ==="
    echo "Operating System: $(get_os_type)"
    echo "Date: $(date)"
    if is_in_docker; then
        echo "Environment: Docker Container"
    fi
    echo

    # Show requested information

    if [ "$show_all" = true ]; then
        get_cpu_arch
        get_cpu_usage
        get_gpu_info
    else
        [ "$show_cpu_arch" = true ] && get_cpu_arch
        [ "$show_cpu" = true ] && get_cpu_usage
        [ "$show_gpu" = true ] && get_gpu_info
    fi
}

# Run main function with all arguments

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
