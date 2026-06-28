# Chromium In Dev Containers

This document records the current Chromium-family browser behavior in these
images and a retained pitfall log for a reverted SUID sandbox design.

Chromium-family here means Chromium, Google Chrome, and Microsoft Edge from
Nixpkgs. Firefox has different wrappers and runtime behavior, so do not use
Firefox success as proof that Chromium has the same launch path.

## Current Use

### `/dev/shm` Size

Docker creates `/dev/shm` as a tmpfs mount. If no size is specified, Docker's
default is `64m`. That is often too small for Chromium's multi-process renderer,
GPU, Skia, and IPC paths. The symptom is usually a renderer, GPU process, or
browser crash soon after launch.

Check the current size:

```sh
df -h /dev/shm
findmnt /dev/shm
```

The better fix is to give the container a larger shared-memory mount at
container creation time. For image or Dockerfile based devcontainers:

```json
{
  "runArgs": ["--shm-size=1g"]
}
```

For Docker Compose based devcontainers:

```yaml
services:
  dev:
    shm_size: "1gb"
```

Recreate or rebuild the devcontainer after changing this. The size is a Docker
runtime setting, not something the image can fix after startup.

`--disable-dev-shm-usage` is a workaround:

```sh
chromium --disable-dev-shm-usage
```

It makes Chromium avoid `/dev/shm` and use `/tmp` instead. This is useful for
quick diagnosis or constrained runtimes, but it can be slower and depends on
available `/tmp` space. Prefer a larger `/dev/shm` for regular interactive use
or browser automation.

Increasing `/dev/shm` mostly changes the memory budget. A `1g` tmpfs limit does
not reserve 1 GB immediately, but data written there consumes host/container
memory. If the container has a tight memory limit, an oversized `/dev/shm` can
turn browser crashes into OOM kills. Avoid very large values unless the host and
container memory budgets are explicit.

Do not use `--ipc=host` or mount the host `/dev/shm` unless the project has
made an explicit isolation decision. `--shm-size=1g` gives the container a
larger private tmpfs; sharing the host IPC namespace or host `/dev/shm` is a
different security tradeoff.

### Sandbox Failures

Chromium-family browsers from Nixpkgs may also fail with sandbox helper errors
in containers:

```text
The SUID sandbox helper binary was found, but is not configured correctly.
You need to make sure that .../__chromium-suid-sandbox is owned by root and has mode 4755.
```

This is independent from GUI forwarding and `/dev/shm`. Passing `--no-sandbox`
can make the browser start, but it disables Chromium's process sandbox. These
images do not add `--no-sandbox`, do not install browser SUID helpers, and do
not relax container runtime security settings by default.

For trusted local development, a project can choose its own launch flags. For
untrusted browsing, browser automation, or CI, decide the runtime threat model
first instead of treating `--no-sandbox` as a harmless compatibility switch.

## SUID Sandbox Pitfalls

This section is intentionally kept as a pitfall log. It is not current image
behavior and it does not describe supported project interfaces. Its purpose is
to stop future work from reintroducing the same SUID sandbox design by accident.

The reverted design tried to keep Chromium-family browsers sandboxed inside
generated devcontainer images without defaulting to `--no-sandbox`. The
implementation proved that helper placement and wrapper patching can be made to
work, but it also showed that Chromium's browser sandbox, Linux namespaces,
seccomp, capabilities, and the OCI runtime profile have to be evaluated
together. A fix that makes the browser launch by weakening the container
runtime profile can make the overall security posture worse.

The current project policy remains:

- do not add `--no-sandbox` globally
- do not bake browser SUID sandbox helpers into the default images
- do not add browser-specific seccomp or capability requirements to make SUID
  helpers work
- let project-specific devcontainer configurations make an explicit
  browser-runtime decision when they need GUI browser execution

### `/run` Is Runtime State

One attempted design placed helper binaries only under:

```text
/run/wrappers/bin
```

That path is runtime state. It can be replaced or hidden by Docker, Dev
Containers, CI runners, or user mounts. Any image asset that exists only under
`/run` can be missing by the time the container starts.

`/run/wrappers/bin` can still matter because Nixpkgs browser wrappers check it,
but it should not be the only persistent location for an image-provided helper.

### Nixpkgs Chromium Can Override Outer Shims

The Nixpkgs Chromium wrapper sets `CHROME_DEVEL_SANDBOX` itself. In simplified
form, it checks for the helper under `/run/wrappers/bin` and otherwise falls
back to the sandbox helper in the Nix store.

That means an outer launcher can set `CHROME_DEVEL_SANDBOX` and still lose:
after the launcher executes the Nixpkgs wrapper, the wrapper may overwrite the
environment variable. If Chromium reports a Nix store sandbox helper path, that
is a strong signal that the wrapper fallback path won.

Bypassing the wrapper is also not a clean answer. The Nixpkgs wrapper sets
runtime details such as library paths, XDG data paths, xdg-utils fallback
commands, and preload filtering. Calling Chromium's unwrapped binary directly
would duplicate that behavior and drift as nixpkgs changes.

### Permission Rules Must Stay Narrow

Another attempted design placed stable helper copies under a broad hierarchy
such as:

```text
/usr/local/lib/devcontainer/browser-sandbox
```

Adding explicit ownership and mode rules for broad directories such as `/usr`
or `/usr/local` can collide with paths already produced by other image layers.
Permission rules for final image tar entries should be as narrow as possible.

The important validation point is the final image tar, not just the Nix store
customization root. Store paths may show normal store ownership while
nix2container permissions determine the actual image tar ownership and SUID
mode.

### Runtime Security Tradeoff Comes First

The reverted work focused on avoiding `--no-sandbox`, but making Chromium's own
SUID sandbox work in a container can push users toward broader seccomp rules,
extra capabilities, or other container profile relaxations. That is not an
acceptable default image policy.

A future browser strategy should start from the container threat model, not
from the Chromium error message. Answer these questions before revisiting helper
placement or wrapper patching:

1. Which runtime profile is required: Docker default, Dev Containers default,
   CI runner default, or something custom?
2. Does enabling the browser sandbox require relaxing seccomp or adding
   capabilities?
3. Is user namespace sandboxing available without extra privileges?
4. Is the browser used for trusted local development only, or for untrusted web
   content?
5. Is headless browser automation better served by a purpose-built image with
   explicit runtime flags?
6. Should the image expose a diagnostic command that prints required runtime
   decisions instead of changing the default image?

### Useful Diagnostics

Check the current shared-memory mount:

```sh
df -h /dev/shm
findmnt /dev/shm
```

Inspect the current Chromium wrapper when Chromium is installed:

```sh
chromium_path="$(command -v chromium)"
printf '%s\n' "$chromium_path"
sed -n '1,140p' "$chromium_path"
```
