# Testing (Phase 0)

## Running

```bash
scripts/test.sh                 # full suite (131 tests)
scripts/test.sh --filter Redaction
```

`scripts/test.sh` wraps `swift test`. With CommandLineTools only (no Xcode),
`Testing.framework` exists but SwiftPM does not add its search path, and the
`_Testing_Foundation` cross-import overlay ships without a swiftmodule — the
script passes the framework path and `-disable-cross-import-overlays`. Under a
full Xcode toolchain, plain `swift test` also works.

## Suites

| Suite | Covers |
|---|---|
| CommandRunner | success, non-zero exit, stdout/stderr separation, stdin delivery + always-closed stdin, timeout kills child, cancellation kills child, missing binary, streaming events, stream timeout |
| IncrementalUTF8Decoder | multi-byte codepoints split across chunks, invalid bytes → U+FFFD, flush, boundary math |
| ContainerBinaryLocator | discovery via PATH/known locations, priority order, missing binary, probe-failing binary, manual selection (uses fake `container` scripts in temp dirs) |
| System JSON decoding | all committed fixtures (running/stopped/unknown-fields/missing-fields), unrecognized status strings, garbage output |
| AppleContainerCLIEngine | verified argument construction, exit-1-with-JSON = stopped, kernel-prompt detection, failure mapping, Phase 1 capability gating (scripted command runner) |
| System lifecycle | initial running/stopped, successful start/stop with polling verification, start-exit-0-but-stopped, stop-exit-0-but-running, start/stop failures, kernel prompt flow, duplicate-mutation prevention, cancellation + resync, auto-start preference, confirmation counts, no-simultaneous-start-stop, stop preserves resources |
| Redaction / validation | env values, password flags (both forms), display command vs executed arguments, resource names, executable paths |
| Resource decoding | every Phase 1 fixture (container list stopped/running, inspects, images, volumes, machines, df, builder, registries), unknown-field tolerance, reference splitting, IP prefix stripping |
| Phase 1 engine reads | verified argument construction for all list commands, stopped-system → serviceNotRunning mapping, network-plugin gating, unverified-stats honesty, inspect input validation |
| ResourceStore | loaded/needsSystem/unavailable/failed transitions, stale-on-stop keeps data, failed refresh never erases data |
| Real CLI integration (read-only) | version/status/discovery + resource reads (tolerant of both system states) against the installed binary; **skipped, never faked** when absent |
| Real CLI lifecycle (opt-in) | full start→verify→stop→verify through `SystemPowerController` against the real CLI |

## Opt-in real lifecycle test

Mutates system state (starts/stops Apple Container), so it is disabled by
default and refuses to run when it finds the system already running:

```bash
CONTAINERDECK_REAL_LIFECYCLE=1 scripts/test.sh --filter RealLifecycle
```

It restores the stopped state afterwards.

## Fixtures

`Tests/ContainerDeckKitTests/Fixtures/*.json` were captured from the real
CLI 1.0.0 (see docs/supported-commands.md). The `-unknown-fields` /
`-missing-fields` variants are hand-derived from the captured ones to prove
decode tolerance.
