# agentic-daemon

A macOS user-space daemon that watches a `jobs/` directory for Swift scripts, auto-compiles them, and runs them on configurable schedules. Drop a Swift script in, and it compiles and runs automatically.

## Quick Start

```bash
# Install and start the daemon
./install.sh

# Create a job
mkdir -p ~/Library/Application\ Support/com.agentic-cookbook.daemon/jobs/hello
cat > ~/Library/Application\ Support/com.agentic-cookbook.daemon/jobs/hello/job.swift << 'EOF'
import Foundation
print("Hello from agentic-daemon! \(Date())")
EOF

# Watch the logs
log stream --predicate 'subsystem == "com.agentic-cookbook.daemon"'
```

## How It Works

1. **launchd** starts the daemon at login and keeps it alive
2. The daemon watches `~/Library/Application Support/com.agentic-cookbook.daemon/jobs/`
3. Each subdirectory with a `job.swift` file is a job
4. Jobs are compiled with `swiftc -O` and cached as `.job-bin`
5. The scheduler runs each job at its configured interval
6. If a source file changes, the daemon recompiles automatically

## Job Directory Structure

```
jobs/
  my-job/
    job.swift       # Swift source (required)
    config.json     # Configuration (optional)
    .job-bin        # Compiled binary (auto-managed)
```

## config.json

All fields are optional. Defaults shown:

```json
{
  "intervalSeconds": 60,
  "enabled": true,
  "timeout": 30,
  "runAtWake": true,
  "backoffOnFailure": true
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `intervalSeconds` | `60` | Seconds between runs |
| `enabled` | `true` | Whether the job is active |
| `timeout` | `30` | Max seconds per run before termination |
| `runAtWake` | `true` | Run immediately after system wake |
| `backoffOnFailure` | `true` | Exponential backoff on consecutive failures |

## Logs

The daemon uses macOS unified logging (`os.log`):

```bash
# Stream all daemon logs
log stream --predicate 'subsystem == "com.agentic-cookbook.daemon"'

# Filter by component
log stream --predicate 'subsystem == "com.agentic-cookbook.daemon" AND category == "Scheduler"'
```

Stdout/stderr are also written to `~/Library/Logs/com.agentic-cookbook.daemon/`.

## Install / Uninstall

```bash
./install.sh     # Build, install binary + plist, start daemon
./uninstall.sh   # Stop daemon, remove binary + plist
```

## Build

```bash
cd AgenticDaemon
swift build              # Debug build
swift build -c release   # Release build
```
