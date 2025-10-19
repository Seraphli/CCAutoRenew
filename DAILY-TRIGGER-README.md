# Claude Daily Trigger - Crontab-Based Daily Trigger

A simple crontab-based solution to automatically trigger Claude sessions at specified times each day. Supports multiple trigger times per day.

## Why Crontab Instead of Daemon?

Since we only need to trigger **once per day**, using crontab is much simpler and more reliable:

- ✅ **No daemon process** - Zero resource usage when idle
- ✅ **System-managed** - Cron service handles scheduling, no custom process management
- ✅ **Auto-starts after reboot** - Cron service starts automatically
- ✅ **Battle-tested** - Uses proven Unix scheduling system
- ✅ **Simple codebase** - ~100 lines vs 250+ lines for daemon version
- ✅ **No state management** - No PID files, no complex state tracking

## Files

- `claude-daily-trigger.sh` - Trigger script called by cron (~100 lines)
- `claude-daily-trigger-manager.sh` - Management script to setup/remove crontab
- `DAILY-TRIGGER-README.md` - This documentation

## Quick Start

### Setup Daily Trigger at 9 AM

```bash
./claude-daily-trigger-manager.sh setup --at 09:00
```

This will:
- Add a crontab entry to run the trigger at 9:00 AM daily
- Configure the system to automatically trigger Claude at that time
- Work automatically even after system reboot

### Setup Multiple Trigger Times

```bash
# Trigger at 3 AM and 5 PM daily
./claude-daily-trigger-manager.sh setup --at 03:00 --at 17:00
```

You can specify `--at` multiple times to set up multiple triggers per day. This is useful for:
- Morning and evening check-ins
- Keeping Claude sessions active throughout the day
- Different triggers for different time zones

### Setup with Custom Message

```bash
./claude-daily-trigger-manager.sh setup --at 09:00 --message "continue yesterday's work"

# Multiple triggers with custom message
./claude-daily-trigger-manager.sh setup --at 08:00 --at 12:00 --at 18:00 --message "daily check-in"
```

If you don't specify `--message`, it will randomly use one of these greetings:
- hi, hello, hey there, good day, greetings, howdy, what's up, salutations

## Management Commands

### Check Status

```bash
./claude-daily-trigger-manager.sh status
```

Example output (single trigger):
```
Status: ✅ Configured

Number of triggers: 1

Trigger times:
  - 09:00 (cron: 0 9 * * *)

Custom message: "continue yesterday's work"

Last triggered: 2025-10-20 09:00:15

Logs: /home/user/.claude-daily-trigger.log
```

Example output (multiple triggers):
```
Status: ✅ Configured

Number of triggers: 2

Trigger times:
  - 03:00 (cron: 0 3 * * *)
  - 17:00 (cron: 0 17 * * *)

Message: Random greetings

Last triggered: 2025-10-20 17:00:08

Logs: /home/user/.claude-daily-trigger.log
```

### View Logs

```bash
# View last 50 log entries
./claude-daily-trigger-manager.sh logs

# Follow logs in real-time
./claude-daily-trigger-manager.sh logs -f
```

### Test Trigger Manually

```bash
./claude-daily-trigger-manager.sh test
```

This runs the trigger immediately for testing purposes.

### Change Time or Message

```bash
# Change to single trigger time
./claude-daily-trigger-manager.sh setup --at 10:00

# Change to multiple trigger times
./claude-daily-trigger-manager.sh setup --at 08:00 --at 17:00

# Change message (keeps existing times)
./claude-daily-trigger-manager.sh setup --at 03:00 --at 17:00 --message "new message"

# Remove custom message (use random greetings)
./claude-daily-trigger-manager.sh setup --at 09:00
```

**Note:** Running `setup` replaces all existing triggers. Always specify all desired times when running setup.

### Remove Daily Trigger

```bash
./claude-daily-trigger-manager.sh remove
```

## How It Works

### Crontab Entry

When you run `setup --at 09:00`, the manager script adds this line to your crontab:

```
0 9 * * * /path/to/claude-daily-trigger.sh # Claude Daily Trigger
```

When you specify multiple times (e.g., `setup --at 03:00 --at 17:00`), it adds multiple crontab entries:

```
0 3 * * * /path/to/claude-daily-trigger.sh # Claude Daily Trigger
0 17 * * * /path/to/claude-daily-trigger.sh # Claude Daily Trigger
```

The cron daemon (system service) then automatically runs the trigger script at each specified time every day.

### Trigger Script Logic

When the trigger script runs:
1. **Check last trigger time** - Skip if triggered less than 6 hours ago (prevents duplicates)
2. **Load message** - Use custom message or random greeting
3. **Trigger Claude** - Send message via `echo "message" | claude`
4. **Record timestamp** - Save trigger time to prevent duplicates
5. **Log result** - Write to log file

### Duplicate Prevention

The trigger script tracks the last trigger time and skips execution if triggered within the last 6 hours. This prevents duplicate triggers if:
- Cron runs multiple times due to system issues
- You manually test the trigger
- System time changes

## Configuration Files

All configuration is saved in home directory:

```
~/.claude-daily-trigger.log              # Log file
~/.claude-daily-trigger-message          # Custom message (optional)
~/.claude-daily-trigger-last             # Last trigger timestamp
```

Plus one crontab entry managed by the system cron service.

## Use Cases

### Case 1: Auto-start Work Every Morning

```bash
./claude-daily-trigger-manager.sh setup --at 08:30 --message "Good morning, let's start today's work"
```

- Automatically triggers Claude at 8:30 AM every day
- Ensures first session starts at a fixed time
- No running processes, just a crontab entry

### Case 2: Fixed Time with Random Greetings

```bash
./claude-daily-trigger-manager.sh setup --at 09:00
```

- Triggers at 9:00 AM daily
- Uses different random greeting each time
- Makes startup more natural

### Case 3: Multiple Times Throughout the Day

```bash
./claude-daily-trigger-manager.sh setup --at 06:00 --at 12:00 --at 18:00
```

- Triggers at 6 AM, noon, and 6 PM daily
- Keeps Claude sessions active throughout the day
- Useful for timezone coverage or frequent renewals

### Case 4: Different Time on Weekends

```bash
# Weekday schedule (requires manual crontab editing)
0 8 * * 1-5 /path/to/claude-daily-trigger.sh # Weekdays

# Weekend schedule
0 10 * * 0,6 /path/to/claude-daily-trigger.sh # Weekends
```

For advanced scheduling like weekday-specific times, you can manually edit crontab with `crontab -e`.

## Comparison: Crontab vs Daemon

| Feature | Daemon Version | Crontab Version |
|---------|---------------|-----------------|
| Running process | Yes (24/7) | No (only when triggering) |
| Resource usage | Low but constant | Zero when idle |
| Code complexity | 250+ lines | ~100 lines |
| State management | PID files, state tracking | Minimal (just timestamp) |
| Reboot handling | Needs restart script | Automatic (cron service) |
| Reliability | Custom process management | System-managed scheduling |
| Debugging | Check process, logs, PID | Check crontab, logs |
| Setup complexity | Start/stop daemon | One-time crontab setup |

## Advantages Over Daemon Approach

1. **Simplicity** - No complex process management, state tracking, or daemon lifecycle
2. **Reliability** - Leverages battle-tested cron service instead of custom daemon
3. **Resource Efficiency** - Zero CPU/memory usage except during the brief trigger moment
4. **System Integration** - Works seamlessly with system reboot, no manual restart needed
5. **Maintainability** - Fewer moving parts, easier to debug and understand

## Troubleshooting

### Trigger Not Running at Scheduled Time

Check:
1. Is cron service running: `systemctl status cron` or `systemctl status crond`
2. Is crontab configured: `./claude-daily-trigger-manager.sh status`
3. Check cron logs: `grep CRON /var/log/syslog` (Ubuntu) or `journalctl -u crond` (other systems)

### Trigger Script Fails

Check:
1. Is `claude` command available: `which claude`
2. Test manually: `./claude-daily-trigger-manager.sh test`
3. Check logs: `./claude-daily-trigger-manager.sh logs`
4. Verify script has execute permission: `ls -la claude-daily-trigger.sh`

### Multiple Triggers in Same Day

This shouldn't happen due to the 6-hour duplicate prevention. If it does:
1. Check logs: `./claude-daily-trigger-manager.sh logs`
2. Verify crontab has only one entry: `crontab -l | grep "Claude Daily Trigger"`
3. Check timestamp file: `cat ~/.claude-daily-trigger-last | xargs -I {} date -d @{}`

## Example Log

```
[2025-10-20 09:00:01] Starting daily Claude trigger...
[2025-10-20 09:00:01] Using custom message: "start work"
[2025-10-20 09:00:06] ✅ Claude session triggered successfully with message: start work
```

## Advanced Crontab Customization

While the manager script provides simple daily scheduling, you can manually edit crontab for advanced schedules:

### Edit Crontab Directly

```bash
crontab -e
```

### Example Advanced Schedules

```bash
# Weekdays only at 9 AM
0 9 * * 1-5 /path/to/claude-daily-trigger.sh # Claude Daily Trigger

# Multiple times per day
0 9 * * * /path/to/claude-daily-trigger.sh # Morning
0 14 * * * /path/to/claude-daily-trigger.sh # Afternoon

# First day of month at 8 AM
0 8 1 * * /path/to/claude-daily-trigger.sh # Monthly
```

**Note:** If you manually edit crontab, the manager's `status` command may not display correctly. Use `crontab -l` to view all entries.

## Migration from Daemon Version

If you previously used the daemon version:

1. Stop the daemon:
   ```bash
   ./claude-daemon-manager.sh stop  # Old script
   ```

2. Setup crontab version:
   ```bash
   ./claude-daily-trigger-manager.sh setup --at 09:00
   ```

3. The crontab version uses different config files, so no conflicts will occur.

## FAQ

### Q: What happens if my computer is off at the scheduled time?

A: The trigger will not run. Cron only runs jobs when the system is on. If you need to guarantee execution even after being off, consider using `anacron` instead of `cron`, though this is more complex.

### Q: Can I have multiple trigger times per day?

A: Yes! Simply specify multiple `--at` parameters:
```bash
./claude-daily-trigger-manager.sh setup --at 03:00 --at 17:00
```

The duplicate prevention (6-hour window) ensures that even if cron runs multiple times due to system issues, the trigger won't execute more frequently than intended.

### Q: How do I see what's in my crontab?

A: Run `crontab -l` to list all crontab entries.

### Q: Does this work on macOS?

A: Yes, macOS has cron built-in. The scripts are compatible with both Linux and macOS.

### Q: What if cron is not running?

A: On most systems, cron is enabled by default. To check/start:
- Ubuntu/Debian: `sudo systemctl start cron`
- Other Linux: `sudo systemctl start crond`
- macOS: Cron is always running

### Q: Can I change the message without changing the time?

A: Yes, just run setup again with the same time but different message:
```bash
./claude-daily-trigger-manager.sh setup --at 09:00 --message "new message"
```

## License

Same as the original project, uses MIT License.
