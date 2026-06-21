# GUI Forwarding In Dev Containers

VS Code Dev Containers can forward GUI endpoints into a container without any
project-specific X11 or Wayland mounts. A forwarded session may expose more than
one variable at the same time, for example `WAYLAND_DISPLAY`, `DISPLAY`, and
`REMOTE_CONTAINERS_DISPLAY`.

The image must choose from the endpoints that are actually available inside the
container. Host desktop session state is not enough, and image build-time
environment is too early.

## Runtime Model

`containerEnv` is static for the lifetime of a container. It is useful for
stable image defaults, but not for GUI forwarding state that can appear when VS
Code starts or attaches. `remoteEnv` affects VS Code and its child processes,
but it is still metadata, not a runtime socket probe.

These images instead use `devcontainer-gui-env` at runtime:

- the entrypoint refreshes `/run/user/1000/devcontainer-gui-env.sh`
- `/etc/profile` and interactive `/etc/bashrc` source that file
- metadata sets `userEnvProbe` to `loginInteractiveShell`
- a `postStart` lifecycle task refreshes the file again after VS Code has had a
  chance to mount or forward GUI resources

The refresh is intentionally best-effort. It updates future shells and VS Code
child processes that run after environment probing. It cannot rewrite the parent
environment of already-started processes.

## Backend Selection

`devcontainer-gui-env refresh` detects a backend in this order:

1. If `DEVCONTAINER_GUI_ENV=0`, GUI toolkit exports are disabled.
2. If `DEVCONTAINER_GUI_BACKEND=wayland`, Wayland is selected only when a
   Wayland socket exists.
3. If `DEVCONTAINER_GUI_BACKEND=x11`, X11 is selected only when `DISPLAY` or
   `REMOTE_CONTAINERS_DISPLAY` is present.
4. In auto mode, a valid Wayland socket wins; otherwise X11 wins if `DISPLAY`
   or `REMOTE_CONTAINERS_DISPLAY` is present; otherwise no GUI backend is
   exported.

Wayland socket validation follows the normal client convention:

- absolute `WAYLAND_DISPLAY` values are checked directly
- relative values are checked under `$XDG_RUNTIME_DIR`
- if `WAYLAND_DISPLAY` is not set yet, the detector scans `/run/user/$uid`,
  `/tmp/user/$uid`, and `/tmp` for entries whose file name contains `wayland`
  and whose path is a Unix socket or a symlink resolving to a Unix socket

For the default image user this usually means:

```sh
test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
```

If a socket is found by scanning and it lives under `$XDG_RUNTIME_DIR`, the
generated environment exports a relative `WAYLAND_DISPLAY`. If the socket lives
elsewhere, it exports the absolute socket path.

## Startup Ordering Pitfall

VS Code may create the Wayland forwarding socket, or a symlink such as
`/run/user/1000/... -> /tmp/...`, before it injects `WAYLAND_DISPLAY` into the
container process environment. In that startup window, `DISPLAY` can already be
present while `WAYLAND_DISPLAY` is still empty.

If detection only trusts environment variables, the entrypoint refresh sees
`DISPLAY` and no `WAYLAND_DISPLAY`, selects X11, and writes an X11-oriented
toolkit environment. Later terminals may already have `WAYLAND_DISPLAY`, but
they can still source the stale generated file from the earlier X11 decision.

The workaround used here is to treat the container-visible socket state as the
source of truth when `WAYLAND_DISPLAY` is missing. The detector scans the
runtime directories for Wayland-named Unix sockets, including symlinks to
sockets. This catches the Dev Containers startup sequence where the socket is
already mounted or linked but the environment variable has not arrived yet.

## Exported Environment

When Wayland is available, the generated file exports:

| Variable | Value |
| --- | --- |
| `XDG_SESSION_TYPE` | `wayland` |
| `GDK_BACKEND` | `wayland,x11` |
| `QT_QPA_PLATFORM` | `wayland;xcb` |
| `SDL_VIDEODRIVER` | `wayland` |
| `CLUTTER_BACKEND` | `wayland` |
| `MOZ_ENABLE_WAYLAND` | `1` |
| `NIXOS_OZONE_WL` | `1` |

When X11 is selected, it exports:

| Variable | Value |
| --- | --- |
| `XDG_SESSION_TYPE` | `x11` |
| `GDK_BACKEND` | `x11` |
| `QT_QPA_PLATFORM` | `xcb` |
| `SDL_VIDEODRIVER` | `x11` |
| `CLUTTER_BACKEND` | `x11` |

It also unsets `MOZ_ENABLE_WAYLAND` and `NIXOS_OZONE_WL`. If `DISPLAY` is empty
and `REMOTE_CONTAINERS_DISPLAY` is present, the generated file fills `DISPLAY`
from `REMOTE_CONTAINERS_DISPLAY` without overriding an already inherited
`DISPLAY`.

When no backend is selected, the generated file unsets the toolkit variables it
manages and leaves raw forwarding variables such as `DISPLAY` and
`WAYLAND_DISPLAY` alone.

## Toolkit Notes

Qt uses `QT_QPA_PLATFORM` to select QPA platform plugins. The value
`wayland;xcb` asks Qt to try Wayland first and keep XCB as a fallback.

GTK/GDK uses a comma-separated backend order. The value `wayland,x11` asks GDK
to try Wayland first and X11 second.

Nixpkgs Chromium and Electron wrappers already know how to derive Ozone Wayland
flags from `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY`. These images do not add a
second browser wrapper and do not call unwrapped browser binaries directly,
because the Nixpkgs wrappers also carry runtime setup such as library paths,
desktop data paths, preload filtering, and other package-specific details.

## Debugging

Inspect the current environment:

```sh
env | sort | grep -E '^(DISPLAY|REMOTE_CONTAINERS_DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|QT_QPA_PLATFORM|GDK_BACKEND|NIXOS_OZONE_WL|MOZ_ENABLE_WAYLAND)='
```

Check the Wayland socket:

```sh
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  case "$WAYLAND_DISPLAY" in
    /*) ls -l "$WAYLAND_DISPLAY" ;;
    *) ls -l "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ;;
  esac
fi
for dir in "/run/user/$(id -u)" "/tmp/user/$(id -u)" /tmp; do
  [ -d "$dir" ] || continue
  for path in "$dir"/*wayland*; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    ls -l "$path"
  done
done
```

Refresh and inspect the generated file:

```sh
devcontainer-gui-env refresh
devcontainer-gui-env status
devcontainer-gui-env print
cat /run/user/1000/devcontainer-gui-env.sh
```

Force X11 for a session:

```sh
DEVCONTAINER_GUI_BACKEND=x11 devcontainer-gui-env refresh
```

Disable managed GUI toolkit exports:

```sh
DEVCONTAINER_GUI_ENV=0 devcontainer-gui-env refresh
```

For image configuration, `devcontainer.gui.forwarding.enable = false` disables
the shell, metadata, and lifecycle integration and sets `DEVCONTAINER_GUI_ENV=0`
by default.

## Limits

This feature only chooses GUI toolkit environment variables. It does not mount
host sockets, grant GPU devices, resize `/dev/shm`, configure DBus or portals,
or change Chromium sandbox policy. Those are container runtime and isolation
decisions that a project should make explicitly.

## References

- Dev Container metadata reference:
  <https://containers.dev/implementors/json_reference/>
- Qt Platform Abstraction:
  <https://doc.qt.io/qt-6/qpa.html>
- GDK backend selection:
  <https://docs.gtk.org/gdk3/func.set_allowed_backends.html>
