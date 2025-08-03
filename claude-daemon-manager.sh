#!/bin/bash

# Claude Daemon Manager - Start, stop, and manage the auto-renewal daemon

DAEMON_SCRIPT="$(cd "$(dirname "$0")" && pwd)/claude-auto-renew-daemon.sh"
PID_FILE="$HOME/.claude-auto-renew-daemon.pid"
LOG_FILE="$HOME/.claude-auto-renew-daemon.log"
START_TIME_FILE="$HOME/.claude-auto-renew-start-time"
STOP_TIME_FILE="$HOME/.claude-auto-renew-stop-time"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

start_daemon() {
    # Parse --at and --stop parameters
    START_TIME=""
    STOP_TIME=""
    
    # Parse parameters
    while [[ $# -gt 1 ]]; do
        case $2 in
            --at)
                START_TIME="$3"
                shift 2
                ;;
            --stop)
                STOP_TIME="$3"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Process start time
    if [ -n "$START_TIME" ]; then
        # Validate and convert start time to epoch
        if [[ "$START_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "HH:MM" - assume today
            START_TIME="$(date '+%Y-%m-%d') $START_TIME:00"
        fi
        
        # Convert to epoch timestamp
        START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_error "Invalid start time format. Use 'HH:MM' or 'YYYY-MM-DD HH:MM'"
            return 1
        fi
        
        # Store start time
        echo "$START_EPOCH" > "$START_TIME_FILE"
        print_status "Daemon will start monitoring at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
    else
        # Remove any existing start time (start immediately)
        rm -f "$START_TIME_FILE" 2>/dev/null
    fi
    
    # Process stop time
    if [ -n "$STOP_TIME" ]; then
        # Validate and convert stop time to epoch
        if [[ "$STOP_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "HH:MM" - assume today
            STOP_TIME="$(date '+%Y-%m-%d') $STOP_TIME:00"
        fi
        
        # Convert to epoch timestamp
        STOP_EPOCH=$(date -d "$STOP_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$STOP_TIME" +%s 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_error "Invalid stop time format. Use 'HH:MM' or 'YYYY-MM-DD HH:MM'"
            return 1
        fi
        
        # Validate that stop time is after start time
        if [ -n "$START_EPOCH" ] && [ "$STOP_EPOCH" -le "$START_EPOCH" ]; then
            print_error "Stop time must be after start time"
            return 1
        fi
        
        # Store stop time
        echo "$STOP_EPOCH" > "$STOP_TIME_FILE"
        print_status "Daemon will stop monitoring at: $(date -d "@$STOP_EPOCH" 2>/dev/null || date -r "$STOP_EPOCH")"
    else
        # Remove any existing stop time
        rm -f "$STOP_TIME_FILE" 2>/dev/null
    fi
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            print_error "Daemon is already running with PID $PID"
            return 1
        fi
    fi
    
    print_status "Starting Claude auto-renewal daemon..."
    nohup "$DAEMON_SCRIPT" > /dev/null 2>&1 &
    
    sleep 2
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            print_status "Daemon started successfully with PID $PID"
            if [ -f "$START_TIME_FILE" ]; then
                START_EPOCH=$(cat "$START_TIME_FILE")
                print_status "Will begin auto-renewal at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
            fi
            print_status "Logs: $LOG_FILE"
            return 0
        fi
    fi
    
    print_error "Failed to start daemon"
    return 1
}

stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_warning "Daemon is not running (no PID file found)"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ! kill -0 "$PID" 2>/dev/null; then
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
    
    print_status "Stopping daemon with PID $PID..."
    kill "$PID"
    
    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            print_status "Daemon stopped successfully"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    print_warning "Daemon did not stop gracefully, forcing..."
    kill -9 "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    print_status "Daemon stopped"
}

status_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_status "Daemon is not running"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if kill -0 "$PID" 2>/dev/null; then
        print_status "Daemon is running with PID $PID"
        
        # Check start/stop time status
        current_epoch=$(date +%s)
        start_epoch=""
        stop_epoch=""
        
        if [ -f "$START_TIME_FILE" ]; then
            start_epoch=$(cat "$START_TIME_FILE")
        fi
        
        if [ -f "$STOP_TIME_FILE" ]; then
            stop_epoch=$(cat "$STOP_TIME_FILE")
        fi
        
        # Determine current status
        if [ -n "$start_epoch" ] && [ "$current_epoch" -lt "$start_epoch" ]; then
            # Before start time
            time_until_start=$((start_epoch - current_epoch))
            hours=$((time_until_start / 3600))
            minutes=$(((time_until_start % 3600) / 60))
            print_status "Status: ⏰ WAITING - Will activate in ${hours}h ${minutes}m"
            print_status "Start time: $(date -d "@$start_epoch" 2>/dev/null || date -r "$start_epoch")"
        elif [ -n "$stop_epoch" ] && [ "$current_epoch" -ge "$stop_epoch" ]; then
            # After stop time
            print_status "Status: 🛑 STOPPED - Monitoring ended for today"
            print_status "Stop time: $(date -d "@$stop_epoch" 2>/dev/null || date -r "$stop_epoch")"
            if [ -n "$start_epoch" ]; then
                # Calculate next day start time
                next_start=$((start_epoch + 86400))
                print_status "Next start: $(date -d "@$next_start" 2>/dev/null || date -r "$next_start")"
            fi
        else
            # Active period
            print_status "Status: ✅ ACTIVE - Auto-renewal monitoring enabled"
            if [ -n "$stop_epoch" ]; then
                time_until_stop=$((stop_epoch - current_epoch))
                if [ "$time_until_stop" -gt 0 ]; then
                    hours=$((time_until_stop / 3600))
                    minutes=$(((time_until_stop % 3600) / 60))
                    print_status "Will stop in ${hours}h ${minutes}m at: $(date -d "@$stop_epoch" 2>/dev/null || date -r "$stop_epoch")"
                fi
            fi
        fi
        
        # Show recent activity
        if [ -f "$LOG_FILE" ]; then
            echo ""
            print_status "Recent activity:"
            tail -5 "$LOG_FILE" | sed 's/^/  /'
        fi
        
        # Show next renewal estimate (only if active)
        if [ ! -f "$START_TIME_FILE" ] || [ "$current_epoch" -ge "$(cat "$START_TIME_FILE" 2>/dev/null || echo 0)" ]; then
            if [ -f "$HOME/.claude-last-activity" ]; then
                last_activity=$(cat "$HOME/.claude-last-activity")
                current_time=$(date +%s)
                time_diff=$((current_time - last_activity))
                remaining=$((18000 - time_diff))
                
                if [ $remaining -gt 0 ]; then
                    hours=$((remaining / 3600))
                    minutes=$(((remaining % 3600) / 60))
                    echo ""
                    print_status "Estimated time until next renewal: ${hours}h ${minutes}m"
                fi
            fi
        fi
        
        return 0
    else
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
}

restart_daemon() {
    print_status "Restarting daemon..."
    stop_daemon
    sleep 2
    start_daemon
}

show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        print_error "No log file found"
        return 1
    fi
    
    if [ "$1" = "-f" ]; then
        tail -f "$LOG_FILE"
    else
        tail -50 "$LOG_FILE"
    fi
}

# Main command handling
case "$1" in
    start)
        start_daemon "$@"
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon "$@"
        ;;
    status)
        status_daemon
        ;;
    logs)
        show_logs "$2"
        ;;
    *)
        echo "Claude Auto-Renewal Daemon Manager"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs} [options]"
        echo ""
        echo "Commands:"
        echo "  start                      - Start the daemon"
        echo "  start --at TIME            - Start daemon but begin monitoring at specified time"
        echo "  start --at TIME --stop END - Start monitoring at TIME, stop at END"
        echo "                               Examples: --at '09:00' --stop '17:00'"
        echo "                                        --at '2025-01-28 09:00' --stop '2025-01-28 17:00'"
        echo "  stop                       - Stop the daemon"
        echo "  restart                    - Restart the daemon"
        echo "  status                     - Show daemon status"
        echo "  logs                       - Show recent logs (use 'logs -f' to follow)"
        echo ""
        echo "The daemon will:"
        echo "  - Monitor your Claude usage blocks within scheduled hours"
        echo "  - Automatically start a session when renewal is needed"
        echo "  - Stop monitoring at specified stop time"
        echo "  - Resume monitoring the next day at start time"
        echo "  - Prevent gaps in your 5-hour usage windows"
        ;;
esac