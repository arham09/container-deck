# ContainerDeck

A lightweight, native macOS control center for [Apple Container](https://github.com/apple/container) — containers, images, machines, storage, networking, and resource usage in one compact, OrbStack-inspired native app.

Built with SwiftUI, Swift 6 strict concurrency, and the Observation framework. No cloud backend, no account, no telemetry. ContainerDeck manages an existing Apple Container installation through its CLI — it never implements its own runtime and never talks to private APIs.

## Status

Public beta — verified against Apple Container CLI **1.0.0**.

## Features

- **System power** — turn Apple Container on and off with verified state transitions and explicit kernel-install consent; binary discovery with honest onboarding when it isn't installed (mock mode runs the full UI offline).
- **Containers** — browse with search and a raw-JSON inspector; run or create through a form with ports, environment (values always redacted), bind mounts, networks, resource limits, and a live command preview (⌘N); start, stop, kill, restart, delete (force is explicit), and prune with confirmations; stream and search container or boot logs with follow/pause and save; open a shell in a running container via your preferred terminal.
- **Images & registries** — pull, tag, save, load, delete, and prune; build from a Dockerfile with streaming output, redacted build args, and a build history; manage the BuildKit builder; log in to registries with the password sent strictly over stdin.
- **Volumes & networks** — create volumes with optional size and labels, delete them with a permanent-data-loss confirmation, and prune unreferenced ones; network management stays capability-gated until the container-network plugin is installed, and the app says exactly why.
- **Linux machines** — create (image, CPUs, memory, home-mount mode, no-boot), boot/stop/delete, change settings with an explicit pending-restart state (never a silent restart), pick the default machine, run one-shot commands, and stream machine or boot logs.
- **Activity & menu bar** — running-resource and disk-usage charts sampled only while visible and bounded to five minutes (per-container CPU/memory stays gated until the CLI's `stats` command emits data); an optional menu-bar item that shares the app's single source of state.
- **Everywhere** — saved run configurations (env values stripped, versioned import/export), a ⌘K command palette, previewed-and-redacted diagnostics export, and a live operations popover showing in-flight progress with a Cancel control where stopping is safe. Package a distributable DMG with `scripts/package-release.sh`.

## Requirements

- Apple silicon Mac, macOS 15+
- Swift 6 toolchain (CommandLineTools is enough; Xcode optional)
- [Apple Container](https://github.com/apple/container) installed — optional: without it the app shows honest installation guidance, and mock mode works fully offline

## Build & run

```bash
swift build                      # build
scripts/test.sh                  # run the test suite (155 tests)
scripts/make-app-bundle.sh       # build release + assemble .build/ContainerDeck.app
open .build/ContainerDeck.app    # launch
```

Run the full UI against realistic mock data (no Apple Container needed):

```bash
CONTAINERDECK_USE_MOCK=1 swift run ContainerDeck
```

Useful scripts:

- `scripts/verify-environment.sh` — checks toolchain, architecture, and CLI availability
- `scripts/capture-fixtures.sh` — re-captures CLI JSON fixtures after upgrading Apple Container
- `scripts/test.sh` — wraps `swift test` with the framework flags needed on CommandLineTools-only machines
- `scripts/make-app-icon.sh` — regenerates the app icon from `logo.png`

Opt-in integration tests that exercise the real CLI (they start/stop Apple Container and create short-lived containers, restoring state afterwards):

```bash
CONTAINERDECK_REAL_LIFECYCLE=1  scripts/test.sh --filter RealLifecycle   # system start/stop workflow
CONTAINERDECK_REAL_CONTAINERS=1 scripts/test.sh --filter RealContainer  # run → logs → stop → delete → prune
CONTAINERDECK_REAL_IMAGES=1     scripts/test.sh --filter RealImage      # pull → tag → delete → prune
```

## Design principles

- **The CLI is the source of truth.** Every command and JSON schema is verified against the installed CLI before anything is decoded; real captured output lives in `Tests/ContainerDeckKitTests/Fixtures/`. Unverified schemas are surfaced as unavailable — never guessed, never simulated.
- **Exit codes are never trusted for state.** `system status` exits non-zero when stopped, and `system start` can fail while the apiserver still comes up. All transitions are verified by polling status.
- **No shell, no secrets.** Child processes run via executable + argument array with stdin always closed; environment values and passwords are redacted from every preview, log, and history entry.
- **Honest degradation.** A stopped system keeps your last data visible and marked stale; capability-gated features (e.g. the missing network plugin, the CLI's empty `stats` output) say exactly why.

## Project layout

```
Sources/ContainerDeckKit/   library: Core (process exec, discovery, security),
                            Domain (models + ContainerEngine protocol),
                            Infrastructure (CLI engine + mock), Features, SharedUI
Sources/ContainerDeck/      thin @main app target
Tests/ContainerDeckKitTests/  155 tests + real CLI fixtures
docs/                       architecture, supported-commands, testing, security
```

## Docs

- `docs/architecture.md` — layers, key decisions, spec deviations
- `docs/supported-commands.md` — verified CLI commands, schemas, and limitations
- `docs/testing.md` — suites and how to run them
- `docs/security.md` — security rules and enforcement
