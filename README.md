# ContainerDeck

A lightweight, native macOS control center for [Apple Container](https://github.com/apple/container) — containers, images, machines, storage, networking, and resource usage in one compact, OrbStack-inspired native app.

Built with SwiftUI, Swift 6 strict concurrency, and the Observation framework. No cloud backend, no account, no telemetry. ContainerDeck manages an existing Apple Container installation through its CLI — it never implements its own runtime and never talks to private APIs.

## Status

**All 7 phases complete (public beta)** — verified against Apple Container CLI **1.0.0**.

| Area | State |
|---|---|
| System power (Turn On / Turn Off with verified state, kernel-install consent) | ✅ Phase 0 |
| Binary discovery + onboarding when Apple Container is missing | ✅ Phase 0 |
| Live operations popover, native Settings window | ✅ Phase 0 |
| Read-only resource manager: Containers, Images, Volumes, Machines, Registries, Builder, Disk usage | ✅ Phase 1 |
| Raw JSON inspect (collapsible tree, search, copy, save) | ✅ Phase 1 |
| Container lifecycle (run/create/start/stop/kill/restart/delete/prune), run form, streaming logs, external terminal | ✅ Phase 2 |
| Pull/tag/save/load/delete/prune images, streaming builds + history, builder lifecycle, registry login (stdin) | ✅ Phase 3 |
| Volume create/delete/prune with confirmations; networks honestly plugin-gated | ✅ Phase 4 |
| Machine create/boot/stop/delete, settings with pending-restart, default selection, one-shot commands, logs | ✅ Phase 5 |
| Activity charts (verifiable metrics, bounded buffers), menu-bar extra with power control | ✅ Phase 6 |
| Saved run configurations (versioned import/export), ⌘K palette, diagnostics export, persistent history, DMG packaging | ✅ Phase 7 |

See `implementation.md` for the full specification and `phase-0.md` … `phase-7.md` for the per-phase plans.

### What you can do today

Turn Apple Container on and off with verified state transitions; browse containers, images, volumes, machines, registries, builder status, and disk usage with search, sorting, persisted column preferences, and raw-JSON inspectors; run or create containers through a form with ports, environment (values always redacted), bind mounts, networks, resource limits, and a live command preview (⌘N); manage container lifecycles — start, stop, kill, restart, delete (force is explicit), prune — with confirmations; stream and search container or boot logs with follow/pause and save; and open a shell in a running container via your preferred terminal. Pull, tag, save, load, delete, and prune images; build images from a Dockerfile with streaming output, redacted build args, and a persisted build history; manage the BuildKit builder; and log in to registries with the password sent strictly over stdin. Create volumes (with optional size and labels), delete them with a permanent-data-loss confirmation, and prune unreferenced ones — network management stays capability-gated until the container-network plugin is installed, and the app says exactly that. Create Linux machines (image, CPUs, memory, home-mount mode, no-boot), boot/stop/delete them, change settings with an explicit pending-restart state (never a silent restart), pick the default machine, run one-shot commands, and stream machine or boot logs. Watch running-resource and disk-usage charts in Activity (sampling only while visible, bounded to five minutes — per-container CPU/memory charts stay gated until the CLI's `stats` command emits data), and control everything from the optional menu-bar item, which shares the app's single source of state. Save run configurations (env values stripped, versioned import/export), summon any action with the ⌘K palette, export previewed-and-redacted diagnostics, and package a distributable DMG with `scripts/package-release.sh`. Every long-running action shows live progress in the operations popover while it runs, with a Cancel control where stopping is safe.

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
