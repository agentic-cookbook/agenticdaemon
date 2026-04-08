# Agentic Daemon

A macOS user-space daemon that watches a jobs directory for Swift scripts, auto-compiles them, and runs them on configurable schedules.

## Purpose

Drop a Swift script into the jobs directory and it compiles and runs automatically. The daemon is managed by launchd, starts at login, and keeps itself alive. Useful for automating recurring tasks written in Swift without manual build steps.

## Key Features

- Automatic Swift script compilation and execution
- File system watching for new/modified jobs
- launchd integration for auto-start and keep-alive
- Configurable schedules per job
- macOS unified logging (`os.log`)

## Tech Stack

- **Language:** Swift
- **Platform:** macOS (user-space daemon)
- **Process Management:** launchd (`com.agentic-cookbook.daemon.plist`)
- **Logging:** os.log (subsystem: `com.agentic-cookbook.daemon`)

## Status

Active development.
