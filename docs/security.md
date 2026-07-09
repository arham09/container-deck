# Security (Phase 0)

Rules from spec §8 and how Phase 0 enforces them:

- **No shell, ever.** Every child process is launched via
  `Process.executableURL` + `Process.arguments` (`CommandRunner`). Nothing in
  production code invokes `/bin/sh`; `ShellCommandFormatter` output is
  display-only and clearly documented as never executed.
- **stdin is always closed** (after an optional write), so an interactive CLI
  prompt can never hang the app — this is load-bearing: CLI 1.0.0's
  `system start` prompts for kernel installation.
- **Redaction before display.** `SecretRedactor` redacts *all* environment
  values (`-e KEY=VALUE` → `KEY=<redacted>`) and password-style flags in both
  `--flag value` and `--flag=value` forms. `CommandRequest` carries separate
  `arguments` (executed) and `redactedArguments` (displayed); operation
  history and previews only ever see the redacted form. Covered by tests.
- **No secrets persisted.** `UserSettings` stores only paths, toggles, and
  intervals. Registry credentials (Phase 3) will go over stdin and are never
  stored by ContainerDeck.
- **Destructive operations confirm first.** Turn Off shows a confirmation
  listing running-resource counts when known; the kernel install requires an
  explicit dialog choice (no silent downloads).
- **Input validation.** `InputValidator` gates resource names and executable
  paths before they reach an argument array; later phases extend it (ports,
  memory sizes, image refs, subnets, mounts).
- **No `try!` / force unwraps / `fatalError`** in production paths.
- **Child processes cannot leak.** Timeout and cancellation terminate children
  with SIGTERM → 2 s grace → SIGKILL (`ProcessTermination`), verified by tests
  that assert a killed `sleep 30` returns promptly.
