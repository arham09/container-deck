# Privacy

- **No telemetry.** ContainerDeck sends nothing anywhere. There is no
  analytics SDK, no crash reporter, no update phone-home.
- **Everything is local.** State lives in `~/Library/Application
  Support/ContainerDeck/` (build history, saved run configurations — all with
  secrets redacted or stripped) and in `UserDefaults` (preferences, table
  column layouts). In-flight operations are tracked in memory only and are not
  persisted.
- **Secrets are never persisted.** Registry passwords go to the CLI via
  stdin and are managed by Apple Container itself. Environment values are
  redacted from every preview/log entry and stripped from saved
  configurations.
- **Diagnostics exports are user-initiated**, previewed before saving, and
  contain only app/CLI versions, system state, and capability flags — no
  secrets.
- **Third-party code:** none. ContainerDeck depends only on Apple frameworks;
  it launches the Apple Container CLI you installed.
