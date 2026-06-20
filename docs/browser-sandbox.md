# Browser Sandbox

This document records the browser sandbox design because it is intentionally more complex than a normal PATH wrapper. The complexity is here to keep the default safe: Chromium-family browsers should use a matching SUID sandbox helper instead of silently falling back to `--no-sandbox`.

## Scope

Browser sandbox support is controlled by:

```nix
{
  devcontainer.browserSandbox.enable = true;
  devcontainer.browserSandbox.preinstalledBrowsers = [ ];
}
```

Supported browser keys are:

- `chromium`
- `google-chrome`
- `microsoft-edge`

`enable = true` means the image carries browser sandbox helpers. It does not mean the image creates fake browser commands. Command shims are created only for browsers that are actually present:

- Flutter images preinstall Chromium, so they get `chromium` and `chromium-browser` shims at build time.
- `devpkg add chromium`, `devpkg add google-chrome`, and `devpkg add microsoft-edge` sync shims after install.
- `devpkg remove ...` syncs shims after removal.
- Managed shims carry the `devcontainers.nix browser sandbox shim` marker. Unmanaged user files are preserved.

## Goals

The design has four non-negotiable goals:

- Do not set `CHROME_DEVEL_SANDBOX` globally. Browser-specific environment belongs in browser command shims only.
- Do not append `--no-sandbox` by default. That disables Chromium's process sandbox and hides configuration bugs.
- Do not share one helper across different Chromium-family packages. Chromium, Google Chrome, and Edge may require different helper builds and API versions.
- Do not create browser command shims when the browser command is absent. A missing browser must stay missing so `command -v google-chrome` is not a false positive.

## Why `/run/wrappers/bin` Is Not Enough

Nixpkgs Chromium expects a SUID helper under `/run/wrappers/bin`:

```sh
if [ -x "/run/wrappers/bin/__chromium-suid-sandbox" ]
then
  export CHROME_DEVEL_SANDBOX="/run/wrappers/bin/__chromium-suid-sandbox"
else
  export CHROME_DEVEL_SANDBOX="/nix/store/...-chromium-...-sandbox/bin/__chromium-suid-sandbox"
fi
```

There are two container-specific problems:

1. `/run` is runtime state. Docker, Dev Containers, or a user launch configuration can replace it with tmpfs or bind mounts. A helper baked into the image at `/run/wrappers/bin/...` can disappear at container startup.
2. The Chromium wrapper overwrites `CHROME_DEVEL_SANDBOX`. An outer shim can export the correct value and then lose it when the Nixpkgs wrapper runs.

When this fails, Chromium reports the nix store helper path. That is a strong signal that the wrapper fallback path won and the shim environment did not survive.

The image therefore installs each helper in two locations:

| Purpose | Path |
| --- | --- |
| Nix wrapper compatibility | `/run/wrappers/bin/<helper>` |
| Stable shim runtime path | `/opt/devcontainer/browser-sandbox/<helper>` |

Both copies must be root-owned with mode `4755` in the final image tar header.

## Helper Mapping

The compiler copies helpers from the pinned nixpkgs packages:

| Browser | Source | Compatibility target | Stable runtime target |
| --- | --- | --- | --- |
| `chromium` | `${pkgs.chromium.sandbox}/bin/__chromium-suid-sandbox` | `/run/wrappers/bin/__chromium-suid-sandbox` | `/opt/devcontainer/browser-sandbox/__chromium-suid-sandbox` |
| `google-chrome` | `${pkgs.google-chrome}/share/google/chrome/chrome-sandbox` | `/run/wrappers/bin/google-chrome-suid-sandbox` | `/opt/devcontainer/browser-sandbox/google-chrome-suid-sandbox` |
| `microsoft-edge` | `${pkgs.microsoft-edge}/share/microsoft/msedge/msedge-sandbox` | `/run/wrappers/bin/microsoft-edge-suid-sandbox` | `/opt/devcontainer/browser-sandbox/microsoft-edge-suid-sandbox` |

If a nixpkgs package moves its helper, the image build should fail. Do not make helper lookup permissive unless the report and tar checks are updated to prove the replacement still comes from the pinned browser package.

## Shim Behavior

Generated shims live in:

```text
$XDG_DATA_HOME/devcontainer/bin
```

For the default user this is:

```text
/home/vscode/.local/share/devcontainer/bin
```

Each shim:

1. Removes its own directory from `PATH`.
2. Resolves the real browser command with `command -v`.
3. Verifies the stable helper is executable.
4. Sets `CHROME_DEVEL_SANDBOX` to the stable helper.
5. Executes the real browser command.

Chromium has one extra step. If the real browser command is a shell wrapper with `export CHROME_DEVEL_SANDBOX=...` lines, the shim writes a temporary patched wrapper under:

```text
$XDG_RUNTIME_DIR/devcontainer-browser-shims
```

or, if that is unavailable:

```text
$TMPDIR/devcontainer-browser-shims-$UID
```

The patch replaces only `export CHROME_DEVEL_SANDBOX=...` lines with the stable helper path and then runs the patched wrapper with `bash -e`. This preserves the rest of the Nixpkgs wrapper, including library path setup, XDG data directories, xdg-utils fallback PATH entries, LD_PRELOAD filtering, and Wayland flags.

This is deliberately narrower than calling the unwrapped Chromium binary directly. Direct execution would have to duplicate all wrapper setup and would be easier to break when nixpkgs changes.

## Compiler Responsibilities

`lib/compiler/browser-sandbox.nix` owns the build-time behavior:

- define browser specs and helper paths
- copy helper binaries into the customization root
- generate preinstalled browser shims
- add nix2container `perms` entries for helper directories, helper files, and preinstalled shims
- emit `browser-sandbox-report.json`

`lib/default.nix` compiles browser sandbox support after the base filesystem and before image/report compilation. `lib/compiler/image.nix` uses the browser sandbox customization root as the final customization root. `lib/compiler/reports.nix` includes the browser sandbox report in both the report directory and CI plan.

Do not put helper files in the base filesystem compiler. They need package-specific SUID permissions and are easier to reason about as one final customization concern.

## Runtime `devpkg` Responsibilities

`runtime/devpkg/main.sh` owns dynamic browser installs:

- `devpkg browser-shims sync` reconciles managed shims with the current profile and current command availability.
- `devpkg add` and `devpkg remove` call the sync command after package changes.
- Profile JSON detection handles packages installed by attr path, while command detection handles already-available browser binaries.
- Managed shims are overwritten or removed; unmanaged files are preserved.

The runtime script must use the same stable helper paths and shim logic as the compiler-generated shims. If one changes, update the other.

## Reports And Tests

The report contract is `browser-sandbox-report.json`:

```json
{
  "enabled": true,
  "helperRoot": "/run/wrappers/bin",
  "runtimeHelperRoot": "/opt/devcontainer/browser-sandbox",
  "helpers": [
    {
      "browser": "chromium",
      "targetPath": "/run/wrappers/bin/__chromium-suid-sandbox",
      "runtimePath": "/opt/devcontainer/browser-sandbox/__chromium-suid-sandbox",
      "mode": "4755",
      "owner": "root:root"
    }
  ],
  "preinstalledBrowsers": ["chromium"],
  "shims": []
}
```

The important checks are:

- `tests/ci/check-reports.py`
  - report exists
  - no global `CHROME_DEVEL_SANDBOX`
  - all three helper mappings are present
  - non-Flutter images do not get browser command shims
  - Flutter gets only `chromium` and `chromium-browser`
- `tests/ci/check-image-tar.py`
  - final image tar headers contain both helper copies
  - helper mode is `4755`
  - helper owner is root:root
- `tests/ci/check-runtime-tools.sh`
  - `devpkg browser-shims sync` creates shims only when browser packages or commands exist
  - sync removes managed shims after uninstall
  - sync preserves unmanaged files
  - generated shims contain stable helper paths and Chromium patch logic
- `tests/ci/check-runtime-validation-scripts.sh`
  - fixture coverage for image tar validation, including both helper paths

Useful verification commands:

```sh
nix fmt
bash -n runtime/devpkg/main.sh
bash -n tests/ci/check-runtime-tools.sh
bash -n tests/ci/check-runtime-validation-scripts.sh
python3 -m py_compile tests/ci/check-image-tar.py tests/ci/check-reports.py tests/ci/check-runtime-evidence.py
nix build .#checks.x86_64-linux.runtime-tools
nix build .#checks.x86_64-linux.runtime-validation-scripts
nix build .#checks.x86_64-linux.image-nix_latest
nix build .#checks.x86_64-linux.reports-flutter_latest
```

Run all `reports-*` checks when changing report schema or preinstalled shim behavior.

## Troubleshooting

If Chromium still reports a nix store sandbox path:

1. Confirm the command is the managed shim:

   ```sh
   command -v chromium
   head -40 "$(command -v chromium)"
   ```

2. Confirm the stable helper exists and is executable:

   ```sh
   ls -l /opt/devcontainer/browser-sandbox/__chromium-suid-sandbox
   ```

3. Confirm the generated patched wrapper uses the stable helper:

   ```sh
   chromium --version || true
   grep CHROME_DEVEL_SANDBOX "$XDG_RUNTIME_DIR/devcontainer-browser-shims/chromium"
   ```

4. If `command -v chromium` points directly into `/nix/store/.../bin/chromium`, the shim directory is missing from `PATH` or appears after the profile path. Check `PATH` and `$XDG_DATA_HOME/devcontainer/bin`.

5. If the helper exists but mode is not SUID in a running container, inspect the image artifact with `tests/ci/check-image-tar.py`. A runtime mount over `/opt` would also hide the stable helper, but that is not part of the supported container contract.

If `devpkg add google-chrome` installs successfully but `command -v google-chrome` is missing, run:

```sh
devpkg browser-shims sync
devpkg list
```

The sync command will not fabricate a command unless the profile or PATH shows the browser is installed.

## Maintenance Checklist

When changing browser sandbox support:

1. Keep helper mapping per browser. Do not reuse the Chromium helper for Chrome or Edge.
2. Keep `/run/wrappers/bin` copies unless nixpkgs wrappers no longer check that path.
3. Keep stable helper paths outside `/run`; `/run` is runtime state.
4. Keep Chromium wrapper patching narrow. Replace only `export CHROME_DEVEL_SANDBOX=...` lines.
5. Keep compiler-generated shims and `devpkg`-generated shims behaviorally equivalent.
6. Update `browser-sandbox-report.json` checks when report fields change.
7. Validate final image tar headers, not only the Nix store customization root. The store root itself may show normal store ownership, while nix2container `perms` determines final image ownership and SUID mode.
8. Re-run `image-nix_latest` after changing helper directory permissions. Adding perms for broad paths such as `/usr` can collide with existing layer entries.

## Adding Another Browser

To add a browser:

1. Add a browser key to `browserOrder` and `browserSpecs` in `lib/compiler/browser-sandbox.nix`.
2. Choose a browser-specific helper name under both helper roots.
3. Add command names in `commands`.
4. Add the same helper and command mapping to `runtime/devpkg/main.sh`.
5. Update report tests, image tar tests, and runtime shim tests.
6. If the browser wrapper overwrites `CHROME_DEVEL_SANDBOX`, either reuse the narrow wrapper patching behavior or document why a different approach is safe.

Do not add a browser to `preinstalledBrowsers` unless the image actually installs that browser package.
