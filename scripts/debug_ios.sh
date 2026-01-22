#!/bin/bash
#
# iOS Debug Helper Script for LiDAR Scanner App
# Usage: ./debug_ios.sh <command> [options]
#
# Commands:
#   screenshot    - Capture screenshot from simulator/device
#   logs          - Stream device logs
#   video         - Record video from simulator
#   ui-tree       - Show UI hierarchy (requires Maestro)
#   diagnose      - Full diagnostics dump
#   install       - Install app on device
#   launch        - Launch app
#   memory        - Show memory stats
#   crash-logs    - Export crash logs
#   tailscale     - Check Tailscale connection
#

set -e

# Configuration
APP_BUNDLE_ID="com.petrzapletal.lidarscanner"
OUTPUT_DIR="${HOME}/Desktop/LiDAR_Debug"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ensure_output_dir() {
    mkdir -p "$OUTPUT_DIR"
}

# Check if running on simulator or device
get_target() {
    if xcrun simctl list devices booted | grep -q "Booted"; then
        echo "simulator"
    elif command -v idevice_id &> /dev/null && idevice_id -l | grep -q "."; then
        echo "device"
    else
        echo "none"
    fi
}

# Commands
cmd_screenshot() {
    ensure_output_dir
    local target=$(get_target)
    local output_file="${OUTPUT_DIR}/screenshot_${TIMESTAMP}.png"

    case $target in
        simulator)
            log_info "Capturing screenshot from simulator..."
            xcrun simctl io booted screenshot "$output_file"
            log_success "Screenshot saved to: $output_file"
            ;;
        device)
            log_info "Capturing screenshot from device..."
            if command -v idevicescreenshot &> /dev/null; then
                idevicescreenshot "$output_file"
                log_success "Screenshot saved to: $output_file"
            else
                log_error "idevicescreenshot not found. Install libimobiledevice: brew install libimobiledevice"
                exit 1
            fi
            ;;
        *)
            log_error "No booted simulator or connected device found"
            exit 1
            ;;
    esac

    # Open the screenshot
    open "$output_file" 2>/dev/null || true
}

cmd_logs() {
    local target=$(get_target)
    local duration=${1:-30}

    case $target in
        simulator)
            log_info "Streaming simulator logs for ${duration}s (Ctrl+C to stop)..."
            log_info "Filtering for: $APP_BUNDLE_ID"
            xcrun simctl spawn booted log stream \
                --level debug \
                --predicate "subsystem == '$APP_BUNDLE_ID' OR processImagePath CONTAINS 'LidarAPP'" \
                --timeout "${duration}s" 2>/dev/null || \
            xcrun simctl spawn booted log stream --level debug --timeout "${duration}s"
            ;;
        device)
            log_info "Streaming device logs..."
            if command -v idevicesyslog &> /dev/null; then
                idevicesyslog | grep -i "lidar"
            else
                log_error "idevicesyslog not found. Install: brew install libimobiledevice"
                exit 1
            fi
            ;;
        *)
            log_error "No booted simulator or connected device found"
            exit 1
            ;;
    esac
}

cmd_video() {
    ensure_output_dir
    local target=$(get_target)
    local duration=${1:-30}
    local output_file="${OUTPUT_DIR}/recording_${TIMESTAMP}.mp4"

    if [ "$target" != "simulator" ]; then
        log_error "Video recording only supported on simulator"
        exit 1
    fi

    log_info "Recording video for ${duration}s..."
    log_info "Output: $output_file"

    # Start recording in background
    xcrun simctl io booted recordVideo "$output_file" &
    local pid=$!

    sleep "$duration"

    # Stop recording
    kill -INT $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true

    log_success "Video saved to: $output_file"
    open "$output_file" 2>/dev/null || true
}

cmd_ui_tree() {
    if ! command -v maestro &> /dev/null; then
        log_warning "Maestro not installed. Installing..."
        curl -Ls "https://get.maestro.mobile.dev" | bash
        export PATH="$PATH:$HOME/.maestro/bin"
    fi

    log_info "Capturing UI hierarchy..."
    maestro hierarchy
}

cmd_diagnose() {
    ensure_output_dir
    local target=$(get_target)
    local diag_dir="${OUTPUT_DIR}/diagnose_${TIMESTAMP}"

    mkdir -p "$diag_dir"

    log_info "Running full diagnostics..."

    # Screenshot
    log_info "1/5 Capturing screenshot..."
    if [ "$target" == "simulator" ]; then
        xcrun simctl io booted screenshot "${diag_dir}/screenshot.png" 2>/dev/null || true
    fi

    # Device info
    log_info "2/5 Collecting device info..."
    if [ "$target" == "simulator" ]; then
        xcrun simctl list devices booted > "${diag_dir}/device_info.txt"
    elif [ "$target" == "device" ]; then
        ideviceinfo > "${diag_dir}/device_info.txt" 2>/dev/null || true
    fi

    # Recent logs
    log_info "3/5 Collecting recent logs..."
    if [ "$target" == "simulator" ]; then
        xcrun simctl spawn booted log show \
            --predicate "processImagePath CONTAINS 'LidarAPP'" \
            --last 5m > "${diag_dir}/recent_logs.txt" 2>/dev/null || true
    fi

    # Crash logs
    log_info "4/5 Collecting crash logs..."
    find ~/Library/Logs/DiagnosticReports -name "*LidarAPP*" -mtime -7 -exec cp {} "${diag_dir}/" \; 2>/dev/null || true

    # System info
    log_info "5/5 Collecting system info..."
    {
        echo "=== System Info ==="
        sw_vers
        echo ""
        echo "=== Xcode Version ==="
        xcodebuild -version
        echo ""
        echo "=== Available Simulators ==="
        xcrun simctl list devices available
    } > "${diag_dir}/system_info.txt"

    # Create archive
    local archive="${OUTPUT_DIR}/diagnose_${TIMESTAMP}.zip"
    cd "$OUTPUT_DIR"
    zip -r "$archive" "diagnose_${TIMESTAMP}"
    rm -rf "$diag_dir"

    log_success "Diagnostics saved to: $archive"
    open "$OUTPUT_DIR"
}

cmd_install() {
    local app_path=${1:-"build/export/LidarAPP.ipa"}
    local target=$(get_target)

    if [ ! -f "$app_path" ]; then
        log_error "App not found at: $app_path"
        exit 1
    fi

    case $target in
        simulator)
            log_info "Installing on simulator..."
            xcrun simctl install booted "$app_path"
            log_success "Installed successfully"
            ;;
        device)
            log_info "Installing on device..."
            if command -v ios-deploy &> /dev/null; then
                ios-deploy --bundle "$app_path"
            else
                log_error "ios-deploy not found. Install: brew install ios-deploy"
                exit 1
            fi
            ;;
        *)
            log_error "No booted simulator or connected device found"
            exit 1
            ;;
    esac
}

cmd_launch() {
    local target=$(get_target)

    case $target in
        simulator)
            log_info "Launching app on simulator..."
            xcrun simctl launch booted "$APP_BUNDLE_ID"
            log_success "App launched"
            ;;
        device)
            log_info "Launching app on device..."
            if command -v idevicedebug &> /dev/null; then
                idevicedebug run "$APP_BUNDLE_ID"
            else
                log_error "idevicedebug not found"
                exit 1
            fi
            ;;
        *)
            log_error "No booted simulator or connected device found"
            exit 1
            ;;
    esac
}

cmd_memory() {
    local target=$(get_target)

    if [ "$target" != "simulator" ]; then
        log_error "Memory stats only supported on simulator"
        exit 1
    fi

    log_info "Memory statistics for LidarAPP:"
    xcrun simctl spawn booted footprint LidarAPP 2>/dev/null || \
        log_warning "App not running or footprint not available"
}

cmd_crash_logs() {
    ensure_output_dir
    local output_file="${OUTPUT_DIR}/crash_logs_${TIMESTAMP}"

    mkdir -p "$output_file"

    log_info "Collecting crash logs..."

    # Mac crash logs
    find ~/Library/Logs/DiagnosticReports -name "*LidarAPP*" -mtime -30 -exec cp {} "${output_file}/" \; 2>/dev/null || true

    # Simulator crash logs
    find ~/Library/Logs/CoreSimulator -name "*crash*" -mtime -7 -exec cp {} "${output_file}/" \; 2>/dev/null || true

    local count=$(ls -1 "$output_file" 2>/dev/null | wc -l)

    if [ "$count" -gt 0 ]; then
        log_success "Found $count crash logs in: $output_file"
        open "$output_file"
    else
        log_warning "No crash logs found"
        rmdir "$output_file" 2>/dev/null || true
    fi
}

cmd_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        log_error "Tailscale CLI not found"
        log_info "Install: brew install tailscale"
        exit 1
    fi

    log_info "Tailscale status:"
    tailscale status

    echo ""
    log_info "Tailscale IPs:"
    tailscale ip -4
}

cmd_help() {
    echo "iOS Debug Helper Script for LiDAR Scanner App"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  screenshot           Capture screenshot from simulator/device"
    echo "  logs [duration]      Stream device logs (default: 30s)"
    echo "  video [duration]     Record video from simulator (default: 30s)"
    echo "  ui-tree              Show UI hierarchy (requires Maestro)"
    echo "  diagnose             Full diagnostics dump"
    echo "  install [path]       Install app on device/simulator"
    echo "  launch               Launch the app"
    echo "  memory               Show memory stats (simulator only)"
    echo "  crash-logs           Export recent crash logs"
    echo "  tailscale            Check Tailscale connection status"
    echo "  help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 screenshot"
    echo "  $0 logs 60"
    echo "  $0 video 15"
    echo "  $0 diagnose"
}

# Main
case ${1:-help} in
    screenshot)
        cmd_screenshot
        ;;
    logs)
        cmd_logs "$2"
        ;;
    video)
        cmd_video "$2"
        ;;
    ui-tree|ui|hierarchy)
        cmd_ui_tree
        ;;
    diagnose|diag)
        cmd_diagnose
        ;;
    install)
        cmd_install "$2"
        ;;
    launch|run)
        cmd_launch
        ;;
    memory|mem)
        cmd_memory
        ;;
    crash-logs|crash)
        cmd_crash_logs
        ;;
    tailscale|ts)
        cmd_tailscale
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        log_error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
