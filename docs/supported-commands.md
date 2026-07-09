# Supported Commands (Phases 0–6)

Verified against **Apple Container CLI 1.0.0**
(commit `ee848e3ebfd7c73b04dd419683be54fb450b8779`, release build)
on macOS 15.7.7 / Apple silicon. Fixtures captured from this version live in
`Tests/ContainerDeckKitTests/Fixtures/`; re-capture with
`scripts/capture-fixtures.sh` after upgrading the CLI and update DTOs if the
schema changed.

## container system version --format json

- Emits a JSON **array** of component entries: `[{"appName","buildType","commit","version"}]`.
- Exit 0 on success.
- Used for: binary validation probes, version display.

## container system status --format json

- Emits a single JSON object:
  `{"apiServerAppName","apiServerBuild","apiServerCommit","apiServerVersion","appRoot","installRoot","status"}`.
- **`status` values observed:** `"running"`, `"unregistered"`. Anything other
  than `"running"` is treated as stopped, preserving the reported string.
- **Exits 1 when the system is not running** while still printing valid JSON —
  ContainerDeck treats valid JSON as authoritative and ignores the exit code.
- Used for: state detection and post-start/post-stop verification polling.

## container system start

- Flags used: `--enable-kernel-install` (only after explicit user consent).
- **Observed:** with no default kernel configured, the CLI prompts
  (`No default kernel configured. Install the recommended default kernel …? [Y/n]`).
  Under ContainerDeck's always-closed stdin this fails with
  `Error: failed to read user input` and exit 1 — **while the apiserver may
  still come up**. ContainerDeck detects the prompt marker, asks the user via
  a native dialog, and re-syncs state from `status`.
- Exit code 0 is never treated as proof of readiness; the app polls `status`
  (1 s interval, 60 s cap) until `"running"`.

## container system stop

- No flags. Exit 0 observed on success; logs are written to output.
- Verified afterwards by polling `status` until it no longer reports
  `"running"` (30 s cap). Stopping preserves all resources.

## Phase 1 — read-only resources (all verified against CLI 1.0.0)

All list commands emit JSON arrays; inspect commands have **no `--format`
flag** and emit pretty-printed JSON arrays by default. When the system is
stopped, read commands exit non-zero with the marker text
*"Ensure container system service has been started"* → mapped to
`serviceNotRunning` (UI keeps last data, marks it stale).

| Command | Schema highlights (see fixtures) |
|---|---|
| `container list [--all] --format json` | `{configuration:{id, creationDate, image.reference, platform, resources.cpus/memoryInBytes, publishedPorts[]:{hostAddress, hostPort, containerPort, proto, count}, …}, id, status:{state, startedDate, networks[].ipv4Address}}` — `state`: "running"/"stopped"; IPs carry a `/24` suffix (stripped for display); `publishedPorts` schema captured live via `-p 127.0.0.1:8080:80/tcp` (fixture container-list-ports.json) |
| `container inspect <id>` | same entry shape as list |
| `container image list --verbose --format json` | `{configuration:{name, creationDate, descriptor.digest}, id, variants[]:{platform, size}}` — attestation variants have platform.os "unknown" and are excluded from architecture display; size = Σ variant sizes (compressed) |
| `container image inspect <ref>` | same entry shape |
| `container volume list --format json` / `volume inspect` | `{configuration:{name, creationDate, driver, format, labels, sizeInBytes, source}, id}` — sizeInBytes is the provisioned sparse size (512 GiB default), not usage |
| `container machine list --format json` | flat: `{id, status, cpus, memory, diskSize, ipAddress, createdDate, default}` — **no image field** |
| `container machine inspect <name>` | superset: adds `image.reference`, `homeMount`, `containerId`, `startedDate`, `userSetup` |
| `container system df --format json` | `{containers/images/volumes: {active, total, sizeInBytes, reclaimable}}` |
| `container builder status --format json` | `[]` when no builder; non-empty row schema **unverified** → only presence + raw JSON exposed |
| `container registry list --format json` | `[]` on the verification install; row schema **unverified** → lenient string/object handling |

### Verified limitations (CLI 1.0.0)

- **`container stats --no-stream --format json` returned `[]` even with a
  running container.** Live CPU/memory usage is therefore not displayed;
  containers show configured limits instead. If a future CLI emits rows,
  the engine reports the schema as unverified rather than guessing.
- **`container network` requires macOS 26+** — the macOS 15 installer ships
  only the `container-network-vmnet` service (default network), not the
  `container-network` CLI plugin. Networks are capability-gated with that
  reason.
- `container create` (and machine create) require a configured default
  kernel even without running the container.

## Phase 2 — container workflow (all verified against CLI 1.0.0)

| Command | Verified behavior |
|---|---|
| `container run` | Full flag set from help (`--name`, `--detach`, `--rm`, `--cpus`, `--memory`, `--arch`, `--platform`, `--workdir`, `--entrypoint`, `--init`, `--read-only`, `--shm-size`, `--env`, `--env-file`, `--label`, `--publish [ip:]host:container[/proto]`, `--network`, `--progress plain`). With `--detach` the container ID is the last non-progress stdout line. |
| `--mount` / `-v` | Exercised live: `--mount type=bind,source=…,target=…[,readonly]` and `-v host:container` both work; the app builds `--mount` specs. |
| `container create` | Same options; requires a configured default kernel even without starting. |
| `container start/stop/kill <id>` | Echo the ID on success. `stop` takes `--time` (default 5 s grace). |
| `container delete [--force] <id>` | **Refuses running containers without `--force`** ("is running and can not be deleted") — the app guards this and makes force explicit. |
| `container prune` | Prints "Reclaimed X in disk space" + deleted IDs; empty output when nothing to prune. |
| `container logs [--boot] [-f] [-n N] <id>` | Streams stdio (or boot log); no per-line timestamps for stdio — the log viewer labels timestamps as arrival times. |
| `container exec -it <id> <cmd>` | Used to build the "Open Terminal" command (executed by the user's terminal, not by the app). |

## Phase 3 — images, builds, builders, registries (verified against CLI 1.0.0)

| Command | Verified behavior |
|---|---|
| `container image pull [--platform] --progress plain <ref>` | Streams progress lines; exit 0 on success. |
| `container image tag <source> <target>` | Echoes the new reference. |
| `container image delete <ref>` | **"Reclaimed … in disk space" arrives on stderr**, reference on stdout — summaries combine both streams. `--force` means ignore-not-found (unlike container delete). |
| `container image prune [--all]` | Dangling only by default; `--all` removes all unused. |
| `container image save --output <path> <refs>` / `image load --input <path>` | Round-trip exercised live (delete → load restored the image). |
| `container build` | Single `-t` tag, `-f` Dockerfile, `--build-arg`, `--label`, `--no-cache`, `--target`, `--cpus/--memory`, `--platform`, `--pull`, `--secret id=…[,env=\|,src=…]`, `--progress plain`, context dir argument. Build-arg values and secret specs are redacted everywhere. |
| `container builder start [--cpus] [--memory] [--dns…]` / `stop` / `delete [--force]` | First start may pull the BuildKit image (generous timeout). |
| `container registry login --username <u> --password-stdin <server>` | **Password via stdin only** — never in argv, never stored, never logged. |
| `container registry logout <registry>` | Removes the login. |

## Phase 4 — volumes & networks (verified against CLI 1.0.0)

| Command | Verified behavior |
|---|---|
| `container volume create [--label k=v] [-s <size>] <name>` | Echoes the name; size defaults to a 512 GiB sparse image. Round-trip exercised live. |
| `container volume delete <names…>` | No force flag exists; the CLI refuses volumes attached to containers and the app surfaces that error verbatim. |
| `container volume prune` | Removes volumes with no container references; prints "Reclaimed …". |
| `container network create/delete` | **Requires macOS 26+** (verified from apple/container docs: "This feature is available on macOS 26 and later"). The macOS 15 installer ships only the container-network-vmnet service (default network), not the container-network CLI plugin. Capability-gated; flag formats intentionally not guessed until observable. |

## Phase 5 — Linux machines (verified against CLI 1.0.0)

| Command | Verified behavior |
|---|---|
| `container machine create [--name] [--cpus] [--memory] [--home-mount ro\|rw\|none] [--set-default] [--no-boot] [--platform] <image>` | Boots by default; `--no-boot` leaves it stopped. Streams progress. |
| `container machine set --name <id> cpus=<n> memory=<size> home-mount=<mode>` | Verified live: values change immediately in `list`; effective in the VM after restart. Only these three keys exist. |
| `container machine set-default <id>` | Verified live. Deleting the default machine warns to pick a new one. |
| `container machine run --name <id> [cmd…]` | One-shot (no TTY in-app); boots the machine if needed. No dedicated `start` verb exists — boot = `machine run`. |
| `container machine logs [--boot] [-f] [-n N] <id>` | Same shape as container logs. |
| `container machine stop <id>` / `delete <id>` | Delete has no force flag. |

## Phase 6 — activity & menu bar

No new CLI commands: Activity samples `list`, `machine list`, and `system df`
on the Settings interval **only while the view is visible** (bounded 5-minute
buffer, no persistence, no overlapping polls). Per-container CPU/memory charts
remain gated on the verified `container stats` limitation. The menu-bar extra
shares the app's single power controller and stores — no dedicated polling.

All specified phases are integrated. Deferred features (spec §36 — Compose,
embedded terminal, XPC, remote hosts, …) remain future considerations.
