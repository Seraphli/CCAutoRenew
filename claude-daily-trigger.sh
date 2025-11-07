#!/bin/bash

# Claude Daily Trigger - Simple cron-based daily trigger
export PATH="$HOME/.nvm/versions/node/v20.16.0/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
fi

LOG_FILE="$HOME/.claude-daily-trigger.log"
LAST_TRIGGER_FILE="$HOME/.claude-daily-trigger-last"
MESSAGE_FILE="$HOME/.claude-daily-trigger-message"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

already_triggered_today() {
    if [ ! -f "$LAST_TRIGGER_FILE" ]; then
        return 1
    fi
    local last_trigger=$(cat "$LAST_TRIGGER_FILE")
    local current_epoch=$(date +%s)
    local time_diff=$((current_epoch - last_trigger))
    if [ "$time_diff" -lt 18000 ]; then
        return 0
    fi
    return 1
}

trigger_claude_once() {
    local selected_message="$1"
    local output_file=$(mktemp)

    (echo "$selected_message" | claude >> "$output_file" 2>&1) &
    local pid=$!
    local count=0
    while kill -0 $pid 2>/dev/null && [ $count -lt 10 ]; do
        sleep 1
        ((count++))
    done
    if kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null
        wait $pid 2>/dev/null
        local result=124
    else
        wait $pid
        local result=$?
    fi

    # Check for API errors in output
    if grep -q "API Error" "$output_file"; then
        cat "$output_file" >> "$LOG_FILE"
        rm -f "$output_file"
        return 2  # Special code for API error
    fi

    # Check for connection errors
    if grep -q "Connection error" "$output_file"; then
        cat "$output_file" >> "$LOG_FILE"
        rm -f "$output_file"
        return 3  # Special code for connection error
    fi

    cat "$output_file" >> "$LOG_FILE"
    rm -f "$output_file"
    return $result
}

trigger_claude() {
    log_message "Starting daily Claude trigger..."
    if already_triggered_today; then
        log_message "Already triggered in the last 5 hours, skipping..."
        return 0
    fi
    if ! command -v claude &> /dev/null; then
        log_message "ERROR: claude command not found"
        return 1
    fi
    local selected_message=""
    if [ -f "$MESSAGE_FILE" ]; then
        selected_message=$(cat "$MESSAGE_FILE")
        log_message "Using custom message: \"$selected_message\""
    else
        local messages=("hi" "hello" "hey there" "good day" "greetings" "howdy" "what's up" "salutations")
        local random_index=$((RANDOM % ${#messages[@]}))
        selected_message="${messages[$random_index]}"
        log_message "Using random greeting: \"$selected_message\""
    fi

    # Retry logic with exponential backoff
    local max_retries=3
    local retry_count=0
    local wait_time=5  # Start with 5 seconds

    while [ $retry_count -lt $max_retries ]; do
        if [ $retry_count -gt 0 ]; then
            log_message "Retry attempt $retry_count/$max_retries after ${wait_time}s wait..."
            sleep $wait_time
        fi

        trigger_claude_once "$selected_message"
        local result=$?

        if [ $result -eq 0 ] || [ $result -eq 124 ]; then
            log_message "✅ Claude session triggered successfully with message: $selected_message"
            date +%s > "$LAST_TRIGGER_FILE"
            return 0
        elif [ $result -eq 2 ]; then
            log_message "⚠️ API Error detected, retrying..."
            ((retry_count++))
            wait_time=$((wait_time * 2))  # Exponential backoff
        elif [ $result -eq 3 ]; then
            log_message "⚠️ Connection error detected, retrying..."
            ((retry_count++))
            wait_time=$((wait_time * 2))  # Exponential backoff
        else
            log_message "ERROR: Failed to trigger Claude session (exit code: $result)"
            return 1
        fi
    done

    log_message "❌ Failed to trigger Claude after $max_retries attempts"
    return 1
}

trigger_claude
