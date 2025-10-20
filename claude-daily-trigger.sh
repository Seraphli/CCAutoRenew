#!/bin/bash

# Claude Daily Trigger - Simple cron-based daily trigger
# This script is meant to be called by cron

# Set PATH to include common locations where claude might be installed
# This is necessary because cron runs with a minimal PATH
export PATH="$HOME/.nvm/versions/node/v20.16.0/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# If nvm is installed, source it to ensure we get the latest node/npm paths
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
fi

LOG_FILE="$HOME/.claude-daily-trigger.log"
LAST_TRIGGER_FILE="$HOME/.claude-daily-trigger-last"
MESSAGE_FILE="$HOME/.claude-daily-trigger-message"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if already triggered today
already_triggered_today() {
    if [ ! -f "$LAST_TRIGGER_FILE" ]; then
        return 1  # Never triggered
    fi

    local last_trigger=$(cat "$LAST_TRIGGER_FILE")
    local current_epoch=$(date +%s)
    local time_diff=$((current_epoch - last_trigger))

    # If less than 6 hours since last trigger, consider it already triggered
    # This prevents duplicate triggers if cron runs multiple times
    if [ "$time_diff" -lt 21600 ]; then
        return 0  # Already triggered today
    fi

    return 1  # Hasn't triggered today
}

# Function to trigger Claude session
trigger_claude() {
    log_message "Starting daily Claude trigger..."

    # Check if already triggered
    if already_triggered_today; then
        log_message "Already triggered in the last 6 hours, skipping..."
        return 0
    fi

    # Check if claude command exists
    if ! command -v claude &> /dev/null; then
        log_message "ERROR: claude command not found"
        return 1
    fi

    # Get message to send
    local selected_message=""

    if [ -f "$MESSAGE_FILE" ]; then
        selected_message=$(cat "$MESSAGE_FILE")
        log_message "Using custom message: \"$selected_message\""
    else
        # Use random greeting
        local messages=("hi" "hello" "hey there" "good day" "greetings" "howdy" "what's up" "salutations")
        local random_index=$((RANDOM % ${#messages[@]}))
        selected_message="${messages[$random_index]}"
        log_message "Using random greeting: \"$selected_message\""
    fi

    # Send message to Claude with timeout
    (echo "$selected_message" | claude >> "$LOG_FILE" 2>&1) &
    local pid=$!

    # Wait up to 10 seconds
    local count=0
    while kill -0 $pid 2>/dev/null && [ $count -lt 10 ]; do
        sleep 1
        ((count++))
    done

    # Kill if still running
    if kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null
        wait $pid 2>/dev/null
        local result=124  # timeout exit code
    else
        wait $pid
        local result=$?
    fi

    # Check result
    if [ $result -eq 0 ] || [ $result -eq 124 ]; then
        log_message "✅ Claude session triggered successfully with message: $selected_message"
        date +%s > "$LAST_TRIGGER_FILE"
        return 0
    else
        log_message "ERROR: Failed to trigger Claude session (exit code: $result)"
        return 1
    fi
}

# Main execution
trigger_claude
