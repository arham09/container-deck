# ContainerDeck — CLAUDE.md

Native macOS control center for Apple Container (SwiftUI, Swift 6 strict concurrency, SwiftPM). All 7 spec phases complete. Spec: `implementation.md`; per-phase plans: `phase-0.md` … `phase-7.md`.

## Commands

```bash
swift build                      # build (zero warnings is the bar)
scripts/test.sh                  # ALWAYS use this, never bare `swift test` (CLT framework flags)
scripts/test.sh --filter <name>  # one suite
scripts/make-app-bundle.sh       # release build + .build/ContainerDeck.app
scripts/make-app-icon.sh         # regenerate Resources/AppIcon.icns from logo.png
scripts/package-release.sh       # DMG (set DEVELOPER_ID for distribution signing)
CONTAINERDECK_USE_MOCK=1 swift run ContainerDeck   # full UI on mock data
```

Opt-in real-CLI tests (mutate system state, restore it): `CONTAINERDECK_REAL_LIFECYCLE=1|REAL_CONTAINERS=1|REAL_IMAGES=1 scripts/test.sh --filter Real…`

## Toolchain quirks (this machine)

- **CommandLineTools only, no Xcode**: `#Preview` macros don't compile — use `PreviewProvider` structs. `swift test` needs the flags `scripts/test.sh` adds.
- macOS 15 target (spec says 26; documented deviation in `docs/architecture.md`).

## Architecture (details: docs/architecture.md)

```
Features/SharedUI (SwiftUI) → Domain (models + ContainerEngine protocol)
  → Infrastructure (AppleContainerCLIEngine | MockContainerEngine)
  → Core/CommandExecution (CommandRunner actor) → installed `container` CLI
```

- `AppEnvironment` is the composition root (SwiftUI environment injection); views never construct engines.
- One `@MainActor` state owner per concern: `SystemPowerController` (7-state enum, never a Boolean), `ResourceCenter`/`ResourceStore` (independent per-resource failure, stale-on-stop), `*ActionsController` per feature.
- Single `Window` scene — `openWindow(id: "main")` must raise, not spawn.

## Iron rules (violating these broke real things)

1. **The installed CLI is the only source of truth.** Never guess a flag or JSON schema — run `container <cmd> --help`, exercise it, capture output into `Tests/ContainerDeckKitTests/Fixtures/`, then write DTOs (all-optional fields). Unverifiable features throw `featureUnavailable` with the real reason — never simulate. Verified behavior lives in `docs/supported-commands.md`; update it when the CLI changes.
2. **Exit codes lie about state.** `system status` exits 1 when stopped (valid JSON wins); `system start` can exit 1 while the apiserver comes up. All transitions verify by polling status.
3. **No shell, ever.** Executable URL + argument array only. stdin always closed (the CLI prompts interactively — kernel install). `ShellCommandFormatter` output is display-only.
4. **Secrets never persist or display.** Env values → `<redacted>` in every preview/history entry; registry passwords via `--password-stdin` only; saved configs strip env values. Tests assert this — keep them passing.
5. **Destructive = confirmed.** Force paths are separate and labeled; prune dialogs state consequences; machine settings never restart silently (pending-restart state).

## Working style (Karpathy guidelines — apply to every change)

1. **Think before coding.** State assumptions; if the CLI behavior is unknown, verify it live instead of assuming. Present interpretations instead of picking silently; push back when a simpler approach exists.
2. **Simplicity first.** Minimum code that solves the ask. No speculative abstractions, configurability, or error handling for impossible cases. "Would a senior engineer call this overcomplicated?" → rewrite.
3. **Surgical changes.** Touch only what the request requires; match existing style; don't refactor or "improve" adjacent code. Remove only orphans your own change created. Every changed line traces to the request.
4. **Goal-driven execution.** Turn tasks into verifiable criteria (failing test → make it pass; behavior → exercise it against the real CLI when it mutates state, restoring the machine afterward). Loop until `swift build` is warning-free and `scripts/test.sh` is green — then report honestly what was and wasn't verified.

## Reporting

Phase-style honesty applies to all work: say what was verified (and how) vs. what wasn't. Never claim CLI integration passed on mock-only evidence.
