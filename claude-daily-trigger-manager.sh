#!/bin/bash

# Claude Daily Trigger Manager - Manage crontab-based daily trigger

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIGGER_SCRIPT="$SCRIPT_DIR/claude-daily-trigger.sh"
LOG_FILE="$HOME/.claude-daily-trigger.log"
MESSAGE_FILE="$HOME/.claude-daily-trigger-message"
LAST_TRIGGER_FILE="$HOME/.claude-daily-trigger-last"
CRON_MARKER="# Claude Daily Trigger"

# Function to parse time and convert to cron format
time_to_cron() {
    local time_input="$1"

    # Validate HH:MM format
    if [[ ! "$time_input" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
        echo "Error: Invalid time format. Use HH:MM (e.g., 09:00)" >&2
        return 1
    fi

    # Extract hours and minutes
    local hour=$(echo "$time_input" | cut -d: -f1)
    local minute=$(echo "$time_input" | cut -d: -f2)

    # Validate ranges
    if [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ]; then
        echo "Error: Hour must be between 0 and 23" >&2
        return 1
    fi

    if [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ]; then
        echo "Error: Minute must be between 0 and 59" >&2
        return 1
    fi

    # Remove leading zeros for cron
    hour=$((10#$hour))
    minute=$((10#$minute))

    echo "$minute $hour * * *"
}

# Function to setup cron job
setup_cron() {
    local trigger_times=()
    local custom_message=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --at)
                trigger_times+=("$2")
                shift 2
                ;;
            --message)
                custom_message="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate at least one trigger time is provided
    if [ ${#trigger_times[@]} -eq 0 ]; then
        echo "Error: At least one --at parameter is required"
        echo "Usage: $0 setup --at HH:MM [--at HH:MM ...] [--message \"your message\"]"
        exit 1
    fi

    # Validate and convert all times to cron format
    local cron_times=()
    for time in "${trigger_times[@]}"; do
        local cron_time=$(time_to_cron "$time")
        if [ $? -ne 0 ]; then
            exit 1
        fi
        cron_times+=("$cron_time")
    done

    # Save custom message if provided
    if [ -n "$custom_message" ]; then
        echo "$custom_message" > "$MESSAGE_FILE"
        echo "Custom message saved: \"$custom_message\""
    else
        rm -f "$MESSAGE_FILE"
        echo "Using random greetings"
    fi

    # Remove existing cron jobs if present
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | grep -v "^PATH=" | crontab -

    # Add new cron jobs for each time
    local new_crontab=$(crontab -l 2>/dev/null)

    # Add PATH environment variable for cron if not already present
    if ! echo "$new_crontab" | grep -q "^PATH="; then
        new_crontab=$(echo "PATH=$HOME/.nvm/versions/node/v20.16.0/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"; echo "$new_crontab")
    fi

    for i in "${!cron_times[@]}"; do
        new_crontab=$(echo "$new_crontab"; echo "${cron_times[$i]} $TRIGGER_SCRIPT $CRON_MARKER")
    done
    echo "$new_crontab" | crontab -

    echo ""
    echo "✅ Daily trigger configured successfully!"
    echo "Trigger times:"
    for i in "${!trigger_times[@]}"; do
        echo "  - ${trigger_times[$i]} (cron: ${cron_times[$i]})"
    done
    echo ""
    echo "The trigger script will run automatically at the specified times."
    echo "Use '$0 status' to check configuration"
    echo "Use '$0 logs' to view trigger logs"
}

# Function to remove cron job
remove_cron() {
    # Check if cron job exists
    if ! crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
        echo "No Claude daily trigger is configured"
        exit 0
    fi

    # Remove cron job and PATH setting
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | grep -v "^PATH=" | crontab -

    echo "✅ Daily trigger removed successfully"
}

# Function to show status
show_status() {
    # Check if cron job exists
    local cron_entries=$(crontab -l 2>/dev/null | grep "$CRON_MARKER")

    if [ -z "$cron_entries" ]; then
        echo "Status: ❌ Not configured"
        echo ""
        echo "Use '$0 setup --at HH:MM [--at HH:MM ...]' to configure daily trigger"
        exit 0
    fi

    echo "Status: ✅ Configured"
    echo ""

    # Count number of triggers
    local count=$(echo "$cron_entries" | wc -l)
    echo "Number of triggers: $count"
    echo ""

    echo "Trigger times:"
    # Parse each cron entry
    while IFS= read -r entry; do
        local cron_schedule=$(echo "$entry" | sed "s| $TRIGGER_SCRIPT $CRON_MARKER||")
        local minute=$(echo "$cron_schedule" | awk '{print $1}')
        local hour=$(echo "$cron_schedule" | awk '{print $2}')
        printf "  - %02d:%02d (cron: %s)\n" "$hour" "$minute" "$cron_schedule"
    done <<< "$cron_entries"

    echo ""

    # Show custom message if set
    if [ -f "$MESSAGE_FILE" ]; then
        local message=$(cat "$MESSAGE_FILE")
        echo "Custom message: \"$message\""
    else
        echo "Message: Random greetings"
    fi

    # Show last trigger time
    if [ -f "$LAST_TRIGGER_FILE" ]; then
        local last_trigger=$(cat "$LAST_TRIGGER_FILE")
        echo ""
        echo "Last triggered: $(date -d "@$last_trigger" 2>/dev/null || date -r "$last_trigger")"
    fi

    echo ""
    echo "Logs: $LOG_FILE"
}

# Function to show logs
show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No logs found"
        exit 0
    fi

    if [ "$1" = "-f" ]; then
        tail -f "$LOG_FILE"
    else
        tail -n 50 "$LOG_FILE"
    fi
}

# Function to test trigger
test_trigger() {
    echo "Testing Claude trigger..."
    echo ""
    "$TRIGGER_SCRIPT"
    echo ""
    echo "Check logs above for result"
}

# Show usage
usage() {
    cat << EOF
Claude Daily Trigger Manager - Crontab-based daily trigger

Usage: $0 <command> [options]

Commands:
  setup         Configure daily trigger in crontab
  remove        Remove daily trigger from crontab
  status        Show current configuration
  logs [-f]     Show trigger logs (use -f to follow)
  test          Manually trigger once for testing

Setup Options:
  --at HH:MM              Time to trigger Claude each day (can be specified multiple times)
  --message "text"        Custom message to send (optional)

Examples:
  # Setup trigger at 9 AM every day
  $0 setup --at 09:00

  # Setup multiple triggers (e.g., 3 AM and 5 PM)
  $0 setup --at 03:00 --at 17:00

  # Setup with custom message
  $0 setup --at 09:00 --message "continue working"

  # Multiple triggers with custom message
  $0 setup --at 08:00 --at 12:00 --at 18:00 --message "daily check-in"

  # Check status
  $0 status

  # View logs
  $0 logs
  $0 logs -f  # follow logs

  # Test trigger manually
  $0 test

  # Remove all triggers
  $0 remove

How it works:
  - Uses system crontab to schedule daily triggers
  - No daemon process needed, zero resource usage when idle
  - Automatic after system reboot (cron service handles it)
  - Simple and reliable
  - Supports multiple trigger times per day

EOF
}

# Main command dispatcher
case "${1:-}" in
    setup)
        shift
        setup_cron "$@"
        ;;
    remove)
        remove_cron
        ;;
    status)
        show_status
        ;;
    logs)
        shift
        show_logs "$@"
        ;;
    test)
        test_trigger
        ;;
    *)
        usage
        exit 1
        ;;
esac
