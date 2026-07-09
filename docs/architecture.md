# ContainerDeck Architecture (Phases 0–1)

## Layers

```text
SwiftUI feature layer        Features/, SharedUI/, App/
        │
        ▼
ContainerEngine protocol     Domain/ContainerEngine.swift
        │
        ▼
AppleContainerCLIEngine      Infrastructure/AppleContainerCLI/
        │
        ▼
CommandRunner actor          Core/CommandExecution/
        │
        ▼
Installed `container` CLI
```

- **Domain** (`Sources/ContainerDeckKit/Domain/`) — stable models (`ContainerSystemState`, `ContainerSystemStatus`, resource summaries, `OperationRecord`) and the `ContainerEngine` protocol. Views and stores depend only on this layer.
- **Infrastructure** — `AppleContainerCLIEngine` (real CLI) and `MockContainerEngine` (previews/tests). CLI JSON is decoded by DTOs (`DTO/`) that track the CLI schema and are mapped (`Mappers/`) to domain models; DTO fields are all optional so unknown/missing fields never break decoding.
- **Core** — process execution (`CommandRunner` actor, `ChildProcess`, `ProcessTermination`, `IncrementalUTF8Decoder`), binary discovery (`ContainerBinaryLocator`), typed errors, redaction, validation, display formatting.
- **App/Features** — `AppEnvironment` (composition root, injected via SwiftUI environment), `SystemPowerController` (single owner of system state), `OperationStore`, `ResourceOverviewStore`, and the views.

## Key decisions

- **Single system-state owner.** `SystemPowerController` is the only place that holds `ContainerSystemState`. Sidebar, dashboard, settings, and menu commands all observe it. State is a 7-case enum, never a Boolean.
- **Exit codes are never trusted for state.** Verified against CLI 1.0.0: `system status` exits 1 when stopped (with valid JSON), and `system start` can exit 1 while the apiserver still comes up. All transitions are verified by polling `system status --format json`.
- **Kernel installs are an explicit user decision.** `system start` prompts interactively when no default kernel is configured. ContainerDeck always runs children with closed stdin (no hangs), detects the prompt marker in output, and surfaces a typed `kernelInstallationRequired` error that the UI turns into a native dialog; only after consent does it re-run with `--enable-kernel-install`.
- **Engine is closure-parameterized on the binary path**, so binary rediscovery never rebuilds the engine, and tests inject fixed paths.
- **`ChildProcess` is `@unchecked Sendable`** wrapping `Process`/`Pipe` (non-Sendable types); all configuration happens before the instance crosses isolation boundaries and the exit code goes through a lock-protected latch. This is the only `@unchecked` in the codebase.
- **`OperationRecord`, not `Operation`** — avoids colliding with `Foundation.Operation`.
- **Per-resource stores (Phase 1).** `ResourceCenter` owns one `ResourceStore<Item>` per resource area; `refreshAll()` fans out concurrently and each store fails independently — one failure never erases another's data. A stopped system marks stores stale (`needsSystem` only when nothing was ever loaded); capability-gated features carry their reason (`unavailable`). Screens share the `resourcePhase` overlay for loading/empty/error/stale states and `ColumnPrefs` for persisted table column customization.
- **Unverified schemas stay unverified.** `container stats` rows, non-empty builder status, and registry rows were not observable on the verification install; the engine exposes presence/raw JSON or throws `featureUnavailable` instead of guessing field names.

## Deviations from the spec (environment-forced)

| Spec | Actual | Why |
|---|---|---|
| macOS 26+ | Deployment target macOS 15 | Dev machine runs macOS 15.7; a 26-only target could not be built, run, or verified here. All APIs used exist on 15. Revisit when a 26 SDK is available. |
| Xcode app target | SwiftPM package + `scripts/make-app-bundle.sh` | Only CommandLineTools are installed (no Xcode). The package opens in Xcode later; the script produces a launchable, ad-hoc-signed `.app`. |
| `#Preview` macros | `PreviewProvider` structs | The previews macro plugin ships only with Xcode. `PreviewProvider` compiles everywhere and Xcode's canvas renders it. |
| Native notifications | Best-effort | `UNUserNotificationCenter` requires a bundle; the packaged app posts notifications, the bare `swift run` binary no-ops. |

## Mock mode

`CONTAINERDECK_USE_MOCK=1` launches the full app against `MockContainerEngine`
with realistic resources and scripted system transitions — no Apple Container
required. Previews use the same wiring via `AppEnvironment.preview(...)`.
