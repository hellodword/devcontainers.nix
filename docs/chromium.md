# Chromium In Dev Containers

This document records the current Chromium-family browser behavior in these
images and the historical sandbox design that was tried and reverted.

Chromium-family here means Chromium, Google Chrome, and Microsoft Edge from
Nixpkgs. Firefox has different wrappers and runtime behavior, so do not use
Firefox success as proof that Chromium has the same launch path.

## Current Use

### GUI Forwarding

VS Code Dev Containers can provide GUI forwarding automatically. In observed
VS Code sessions it sets variables such as:

```sh
DISPLAY=:0
WAYLAND_DISPLAY=vscode-wayland-...sock
```

That means GUI forwarding may exist even when no project `devcontainer.json`
declares explicit X11 or Wayland mounts. Check the actual running container:

```sh
env | sort | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR)='
test -n "${WAYLAND_DISPLAY:-}" && ls -l "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
```

Chromium can still fail with X11 authorization errors:

```text
Authorization required, but no authorization protocol specified
ERROR:ui/ozone/platform/x11/ozone_platform_x11.cc:257] Missing X server or $DISPLAY
ERROR:ui/aura/env.cc:246] The platform failed to initialize. Exiting.
```

This is an X11 startup failure. The `/run/dbus/system_bus_socket` message often
appears in the same log, but it is usually a warning rather than the fatal
condition for this failure mode.

If the VS Code session provides Wayland but Chromium still takes the X11 path,
pass an explicit platform argument when launching Chromium:

```sh
chromium --ozone-platform=wayland
```

The project does not inject this argument by default. Browser launch policy is
left to the project or user command because GUI forwarding differs across VS
Code, Dev Containers CLI, Docker, CI, local desktop sessions, and remote hosts.

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

## Historical SUID Sandbox Attempt

This section preserves the design notes from the reverted browser SUID sandbox
work. It is historical context, not current image behavior.

The goal was to keep Chromium-family browsers sandboxed inside the generated
devcontainer images without defaulting to `--no-sandbox`. The implementation
was technically workable, but the container security tradeoff was not
acceptable: preserving Chromium's SUID sandbox can require relaxing the
container runtime profile, especially seccomp behavior, which can weaken the
container boundary more than the browser sandbox helps.

### Outcome

The implementation was removed. The current project should not carry browser
SUID helpers, browser sandbox shims, or browser-sandbox reports unless a new
design explicitly revisits the container-runtime security model.

The main lesson is that browser sandboxing cannot be evaluated only at the
browser process level. In containers, the browser sandbox, Linux namespaces,
seccomp, capabilities, and the OCI runtime profile interact. If making
Chromium's SUID sandbox work pushes users toward broader seccomp or privilege
changes, the net security posture can get worse.

### Original Problem

Chromium-family browsers from Nixpkgs can fail in containers with errors around
the SUID sandbox helper. The naive workaround is to pass:

```sh
--no-sandbox
```

That is easy, but it disables Chromium's process sandbox. The reverted design
attempted a safer default:

- do not append `--no-sandbox`
- provide the matching browser helper from the pinned nixpkgs package
- set `CHROME_DEVEL_SANDBOX` only for the browser command
- avoid a global environment variable
- avoid fake `chromium`, `google-chrome`, or `microsoft-edge` commands when the
  browser is not installed

The initial user-facing target was Flutter images because they preinstall
Chromium for web workflows.

### Browser Mapping

The attempted design used separate helpers per browser:

| Browser | Helper source | Helper name |
| --- | --- | --- |
| `chromium` | `${pkgs.chromium.sandbox}/bin/__chromium-suid-sandbox` | `__chromium-suid-sandbox` |
| `google-chrome` | `${pkgs.google-chrome}/share/google/chrome/chrome-sandbox` | `google-chrome-suid-sandbox` |
| `microsoft-edge` | `${pkgs.microsoft-edge}/share/microsoft/msedge/msedge-sandbox` | `microsoft-edge-suid-sandbox` |

The per-browser mapping was important. Chromium's documentation and source
expect the helper API version to match the browser. Reusing a single helper
across Chromium, Chrome, and Edge risks version or API mismatch failures.

### First Design

The first design copied helpers into:

```text
/run/wrappers/bin
```

and set final image tar permissions through nix2container `perms`:

```text
owner: root:root
mode: 4755
```

Command shims were generated under:

```text
$XDG_DATA_HOME/devcontainer/bin
```

For the default user this is:

```text
/home/vscode/.local/share/devcontainer/bin
```

Each shim removed its own directory from `PATH`, resolved the real browser
command, exported `CHROME_DEVEL_SANDBOX`, and then executed the real browser.

The intended shim behavior was:

```sh
shim_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
filtered_path="$(filter_path_without_dir "$shim_dir")"
real_browser="$(PATH="$filtered_path" command -v "$browser_command")"
export CHROME_DEVEL_SANDBOX="$sandbox_helper"
exec "$real_browser" "$@"
```

This avoided global environment changes and avoided creating commands for
absent browsers.

### First Pitfall: `/run` Is Runtime State

Putting image assets only under `/run` is fragile. `/run` is runtime state and
can be replaced by the container runtime, Docker, Dev Containers, or user
mounts. A helper present in the image layer at `/run/wrappers/bin/...` can be
hidden or missing at container startup.

This was observed as a browser launch failure where Chromium still reported the
nix store sandbox path. That pointed to the Nixpkgs wrapper falling back rather
than the shim environment winning.

The key lesson is that `/run/wrappers/bin` can be useful for compatibility with
Nix wrappers, but it should not be the only persistent location for an
image-provided helper.

### Second Pitfall: Nixpkgs Chromium Overrides The Shim

The pinned Nixpkgs Chromium wrapper contains logic equivalent to:

```sh
if [ -x "/run/wrappers/bin/__chromium-suid-sandbox" ]
then
  export CHROME_DEVEL_SANDBOX="/run/wrappers/bin/__chromium-suid-sandbox"
else
  export CHROME_DEVEL_SANDBOX="/nix/store/...-chromium-...-sandbox/bin/__chromium-suid-sandbox"
fi
```

That means an outer shim can set `CHROME_DEVEL_SANDBOX` correctly and still
lose. Once the shim executes the Nixpkgs `chromium` wrapper, the wrapper
overwrites the variable. If `/run/wrappers/bin` is hidden or absent, the wrapper
sets the nix store fallback path.

The error message mentioning the nix store helper path is therefore a strong
signal that the wrapper fallback path won.

### Second Design

The second design kept compatibility copies under:

```text
/run/wrappers/bin
```

but added stable helper copies under:

```text
/opt/devcontainer/browser-sandbox
```

The shim then used the stable `/opt` path for `CHROME_DEVEL_SANDBOX`.

Chromium needed an extra wrapper patch. Instead of calling Chromium's unwrapped
binary directly, the shim copied the Nixpkgs wrapper into a temporary runtime
path and replaced only lines matching:

```sh
export CHROME_DEVEL_SANDBOX=...
```

with the stable helper path. The patched wrapper was then run with `bash -e`.

The reason for patching the wrapper instead of bypassing it was that the
Nixpkgs wrapper also sets useful runtime details:

- `LD_LIBRARY_PATH`
- `XDG_DATA_DIRS`
- xdg-utils fallback `PATH`
- `LD_PRELOAD` filtering for `libredirect`
- Wayland flags derived from `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY`

Calling the unwrapped Chromium binary directly would have required duplicating
all of that behavior and would be likely to drift when nixpkgs changes.

### Third Pitfall: Broad Directory Permissions Can Collide In Image Layers

The stable helper was first placed under:

```text
/usr/local/lib/devcontainer/browser-sandbox
```

The final image check failed because adding explicit permissions for broad
directories such as `/usr` collided with paths already produced by other
layers. The fix was to use:

```text
/opt/devcontainer/browser-sandbox
```

and keep permission rules narrow.

The lesson is to validate final nix2container image tar headers, not just the
Nix store customization root. The store root may show normal store ownership
while nix2container `perms` determine the actual image tar ownership and SUID
mode.

### Runtime `devpkg` Work

The attempted runtime integration added:

```sh
devpkg browser-shims sync
```

`devpkg add` and `devpkg remove` called the sync command after package changes.
The sync logic:

- detected installed browser packages from `nix profile list --json`
- also checked command availability on `PATH`
- generated shims only for installed browsers
- removed managed shims after uninstall
- preserved unmanaged user files

This behavior was useful independently of the sandbox mechanics because it
avoided false-positive browser commands. If future work reintroduces browser
wrappers for a different purpose, preserve that constraint.

### Report And Test Work

The reverted implementation added a `browser-sandbox-report.json` report with:

- helper root paths
- browser-to-helper mapping
- helper source package paths
- expected mode and owner
- preinstalled browser list
- generated shim metadata

Tests were added or extended to check:

- no global `CHROME_DEVEL_SANDBOX`
- all helper mappings were reported
- non-Flutter images did not get browser command shims
- Flutter got only `chromium` and `chromium-browser`
- final image tar headers contained helpers with root:root `4755`
- `devpkg browser-shims sync` created, removed, and preserved shims correctly
- a fake Chromium wrapper that tried to fall back to a nix store helper was
  patched to use the stable helper path

If a future design uses generated browser shims again, the fake wrapper test is
worth keeping conceptually because it catches the exact Nixpkgs wrapper
override problem.

### Why The Design Was Reverted

The implementation focused on avoiding `--no-sandbox`, but making Chromium's
own sandbox work in a container can push the user toward container runtime
relaxations. In particular, browser sandbox startup can interact with:

- seccomp syscall filtering
- namespace creation
- setuid execution behavior
- container capabilities
- runtime-specific defaults from Docker, Dev Containers, or CI runners

If the fix for browser startup is to broaden seccomp, add capabilities, or
otherwise weaken the container runtime profile, the container boundary may
become less safe overall. That tradeoff is not acceptable as a default image
policy.

The safer project-level conclusion is:

- do not bake browser SUID sandbox helpers by default
- do not add browser-specific seccomp or privilege requirements to make the
  SUID helper work
- do not silently add `--no-sandbox` as a global default
- let project-specific devcontainer configurations make an explicit
  browser-runtime decision when they need GUI browser execution

### Future Considerations

A future browser strategy should start from the container threat model, not from
the browser error message. Questions to answer first:

1. Which exact runtime profile is required: Docker default, Dev Containers
   default, CI runner default, or something custom?
2. Does enabling the browser sandbox require relaxing seccomp or adding
   capabilities?
3. Is user namespace sandboxing available without extra privileges?
4. Is the browser used for trusted local development only, or for untrusted web
   content?
5. Is headless browser automation better served by a purpose-built image with
   explicit runtime flags?
6. Should the image expose a helper command that prints required runtime flags
   instead of changing the default image?

Only after those questions are answered should implementation details such as
helper placement, wrapper patching, and `devpkg` shim syncing be revisited.

### Historical Investigation Commands

Inspect the Nixpkgs Chromium wrapper:

```sh
nix build nixpkgs#chromium --no-link --print-out-paths
sed -n '1,120p' /nix/store/...-chromium-.../bin/chromium
```

Check report output from the reverted implementation:

```sh
nix eval --json .#images.flutter-latest.browserSandbox.report
```

Check generated shim content from the reverted implementation:

```sh
nix build .#images.flutter-latest.browserSandbox.root --no-link --print-out-paths
sed -n '1,180p' /nix/store/...-flutter-latest-customization-root/home/vscode/.local/share/devcontainer/bin/chromium
```

Validate final image tar headers:

```sh
nix build .#checks.x86_64-linux.image-nix_latest
```

These commands are historical. They may not work after the revert unless a
future branch reintroduces the relevant outputs.
