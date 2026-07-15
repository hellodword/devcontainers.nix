# Fonts And Fontconfig

This document explains the default font and fontconfig design for all published
images. It is intended for maintainers changing the image contract, package set,
font fallback order, or fontconfig generation code.

## Goals

All main images should have a predictable baseline for GUI tools, browser based
tooling, editor extensions, and CLIs that render text through fontconfig.

The default contract is:

- fontconfig is installed, including `fc-cache`, `fc-list`, `fc-match`,
  `fc-query`, `fc-scan`, `fc-validate`, `fc-cat`, `fc-conflist`, and
  `fc-pattern`
- `noto-fonts`, `noto-fonts-cjk-sans`, `noto-fonts-cjk-serif`, and
  `noto-fonts-color-emoji` are installed
- Simplified Chinese CJK fallback is preferred for generic sans, serif, and
  monospace families
- emoji resolves to `Noto Color Emoji`
- symbol coverage comes from `Noto Sans Symbols` and `Noto Sans Symbols 2` in
  `noto-fonts`
- user fontconfig overrides under `~/.config/fontconfig` are enabled by default
- `FONTCONFIG_FILE` is not set globally
- fontconfig caches are not pre-generated into the image

The design optimizes for reliable font discovery and broad fallback coverage,
not desktop rendering preference management.

## Non Goals

The module does not expose the full NixOS fontconfig surface. In particular, it
does not manage hinting, subpixel rendering, bitmap font policy, Type 1 policy,
or other desktop rendering preferences.

The module also does not build a system font cache. Pre-generating caches would
increase image build work and cache invalidation complexity. Fontconfig can scan
the Nix store font directories directly and write user cache entries on first
use.

## Public API

The options live under `devcontainer.fonts` and are declared in
`lib/modules/core/fonts.nix`.

Default configuration:

```nix
devcontainer.fonts = {
  enable = true;
  packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

  fontconfig = {
    enable = true;
    package = pkgs.fontconfig;
    includeUserConf = true;
    localConf = "";
    defaultFonts = {
      sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
      serif = [ "Noto Serif CJK SC" "Noto Serif" ];
      monospace = [ "Noto Sans Mono CJK SC" "Noto Sans Mono" ];
      emoji = [ "Noto Color Emoji" ];
    };
    aliases = { };
  };
};
```

`defaultFonts` and `aliases` intentionally follow the NixOS module's API
semantics. This keeps the familiar shape without importing the NixOS module or
desktop-specific font management behavior.

Alias entries use:

```nix
devcontainer.fonts.fontconfig.aliases."Helvetica" = {
  binding = "same";
  prefer = [ ];
  accept = [ ];
  default = [ "Noto Sans" ];
};
```

Valid `binding` values are `same`, `weak`, and `strong`.

## Module Layering

`lib/modules/core/fonts.nix` is discovered by the module registry in
`lib/modules/default.nix`, so every image target inherits the font baseline.

When enabled, the module:

- adds the configured font packages to `environment.systemPackages`
- appends the configured fontconfig package when `fontconfig.enable = true`
- creates graph node `runtime/fonts`
- assigns the node to bucket `fonts-runtime`
- declares owner-local smoke cases for tool availability, CJK matching, and
  emoji matching

The module declares bucket definition `fonts-runtime` with order `200`,
immediately after the base and FHS runtime buckets. That keeps the font runtime
shared and stable across language image families.

## Compiler Flow

The font compiler is `lib/compiler/fonts.nix`.

It produces two values:

- `root`: a small generated root containing `/etc/fonts`
- `report`: the JSON payload used for `fontconfig-report.json`

`lib/default.nix` wires the compiler into `mkImage` and passes the result to the
filesystem, image, and report compilers.

The final OCI image does not add the font root as a separate final
`copyToRoot` entry. `lib/compiler/filesystem.nix` copies `compiledFonts.root`
into the generated filesystem root instead. This avoids duplicate `/etc`
entries in the final tar when nix2container applies filesystem permissions.

`lib/compiler/image.nix` still includes `compiledFonts.root` in the local
`rootfs` build environment. That makes the rootfs output useful for inspection
while the final image path stays collision free.

## Generated Files

The generated filesystem contains:

- `/etc/fonts/fonts.conf`
- `/etc/fonts/conf.d/*` standard fontconfig configuration symlinks
- `/etc/fonts/conf.d/52-devcontainer-default-fonts.conf`
- `/etc/fonts/conf.d/53-devcontainer-aliases.conf`
- `/etc/fonts/local.conf` when `devcontainer.fonts.fontconfig.localConf` is not
  empty

`/etc/fonts/fonts.conf` comes from `pkgs.makeFontsConf` with:

```nix
pkgs.makeFontsConf {
  fontconfig = config.devcontainer.fonts.fontconfig.package;
  fontDirectories = config.devcontainer.fonts.packages;
  includes = [ "/etc/fonts/conf.d" ];
}
```

The compiler uses `lib.getOutput "out" fontconfig.package` when linking
fontconfig's stock configuration files because the `fontconfig` package has
separate `bin`, `dev`, `lib`, and `out` outputs. Command binaries come from the
package path in the graph, while stock config files come from the `out` output.

When `includeUserConf = false`, `50-user.conf` is omitted from the generated
`conf.d` tree. By default it is kept, allowing:

- `~/.config/fontconfig/conf.d`
- `~/.config/fontconfig/fonts.conf`

`localConf` is written as `/etc/fonts/local.conf`. The stock `51-local.conf`
already includes `local.conf`, so no separate custom include rule is needed.

## Default Fonts

The default aliases are generated in
`52-devcontainer-default-fonts.conf` with `binding="same"`.

Defaults:

- `sans-serif`: `Noto Sans CJK SC`, then `Noto Sans`
- `serif`: `Noto Serif CJK SC`, then `Noto Serif`
- `monospace`: `Noto Sans Mono CJK SC`, then `Noto Sans Mono`
- `emoji`: `Noto Color Emoji`

The SC order is intentional. It gives Simplified Chinese glyph forms for CJK
code points where regional variants differ, for example `门` and `复`, while
still keeping Latin and general fallback from the Noto families.

`noto-fonts` is included even though CJK packages provide many glyphs because it
supplies Latin families, `Noto Sans Mono`, and symbol fonts. The smoke test uses
U+23FB to verify symbol fallback through `Noto Sans Symbols 2`.

## Cache Policy

The compiler does not call `pkgs.makeFontsCache` and does not add a generated
cache path. `fontconfig-report.json` records this as:

```json
{
  "cache": {
    "preGenerated": false,
    "systemCacheDir": "/var/cache/fontconfig",
    "userCache": "$XDG_CACHE_HOME/fontconfig"
  }
}
```

At runtime, fontconfig reads the store font directories listed in
`/etc/fonts/fonts.conf`. On first use it may create cache files under the user's
XDG cache directory. This can make the first `fc-match` or GUI process slightly
slower, but it avoids baking architecture specific cache artifacts into every
image layer.

Do not add `FONTCONFIG_FILE` to the image environment. The image provides the
standard `/etc/fonts/fonts.conf`, so fontconfig's normal lookup path is enough.
Leaving the environment unset also lets project specific tools override it
locally when needed.

## Reports And CI

`lib/compiler/reports.nix` writes `fontconfig-report.json` and lists it in
`ci-plan.json`.

The report records:

- enabled state
- configured font packages
- fontconfig package and config paths
- `includeUserConf`
- `localConf` state
- default fonts
- aliases
- required `fc-*` tools
- global `FONTCONFIG_FILE` policy
- cache policy

`flake/checks/contracts/reports/fonts.nix` rejects regressions in the public
font report contract:

- missing `fontconfig-report.json`
- missing `fonts-runtime` or `runtime/fonts`
- missing required font packages
- missing required `fc-*` tools
- non-SC default font order
- non-empty default aliases
- disabled user config includes
- global `FONTCONFIG_FILE`
- pre-generated cache

`flake/checks/contracts/reports/smoke.nix` verifies declared smoke cases are
present in generated smoke plans. Font smoke cases live with the owning font
module:

- `fontconfig.core`
- `fontconfig.cjk-emoji`

The image tar fixture check exercises the artifact validator on representative
layer-plan inputs, and runtime smoke tests validate font behavior after an image
is loaded into Docker.

## Useful Validation Commands

Build the generated font root:

```sh
nix build .#images.dev.fonts.root --print-out-paths --no-link
```

Build reports for one image:

```sh
nix build .#images.dev.reports
```

Build the image tar check for the reference image:

```sh
nix build .#checks.x86_64-linux.artifact-image-dev
```

After loading an image, run the normal smoke plan:

```sh
nix run .#load-dev
nix run .#run-smoke-plan -- dev
```

Useful manual checks inside a container:

```sh
command -v fc-cache fc-list fc-match fc-query fc-scan fc-validate fc-cat fc-conflist fc-pattern
fc-match 'sans-serif:lang=zh-cn:charset=0x95e8'
fc-match 'sans-serif:lang=zh-cn:charset=0x590d'
fc-match 'serif:lang=zh-cn:charset=0x95e8'
fc-match 'monospace:lang=zh-cn:charset=0x95e8'
fc-match 'emoji:charset=0x1f600'
fc-match 'sans-serif:charset=0x23fb'
```

Expected families are `Noto Sans CJK SC`, `Noto Serif CJK SC`,
`Noto Sans Mono CJK SC`, `Noto Color Emoji`, and `Noto Sans Symbols 2`.

## Maintenance Guide

When changing default font packages:

1. Update `devcontainer.fonts.packages` defaults in
   `lib/modules/core/fonts.nix`.
2. Update `fontconfig-report.json` assertions in `flake/checks/contracts/reports/fonts.nix`.
3. Update smoke tests in `lib/modules/core/fonts.nix` if coverage expectations
   changed.
4. Update `README.md`, `docs/usage.md`, and this document.
5. Run the report and image checks listed above.

When changing default fallback order:

1. Update `devcontainer.fonts.fontconfig.defaultFonts`.
2. Verify `fc-match` results for representative CJK code points.
3. Update `flake/checks/contracts/reports/fonts.nix` and `fontconfig.cjk-emoji` smoke expectations.
4. Document the rationale, especially if changing regional CJK priority.

When adding system cache generation:

1. Decide whether the cache is architecture specific and how cross builds should
   behave.
2. Add the generated cache to the image deliberately, not as an accidental side
   effect.
3. Change `fontconfig-report.json` from `preGenerated = false`.
4. Update report checks, docs, and smoke expectations.

When exposing rendering controls:

1. Prefer small generated fontconfig snippets over importing the NixOS module.
2. Keep options scoped to container needs.
3. Avoid changing rendering defaults unless there is a concrete image runtime
   bug. Font rendering preferences are subjective and easy to regress.

## Troubleshooting

If `fc-match` returns DejaVu or misses Noto CJK:

- check that `/etc/fonts/fonts.conf` exists in the filesystem root
- check that `/etc/fonts/conf.d/52-devcontainer-default-fonts.conf` exists
- check that `runtime/fonts` is present in `graph.json`
- check that the Noto packages are listed in `fontconfig-report.json`
- check that `FONTCONFIG_FILE` is not set to a project or host path

If CJK glyphs resolve to the wrong regional variant:

- include `lang=zh-cn` in diagnostic `fc-match` commands
- verify the SC family is first in the relevant `defaultFonts` list
- inspect `~/.config/fontconfig` for user overrides

If nix2container reports duplicate `/etc` entries while building the final
image:

- keep `/etc/fonts` merged through `compiledFilesystem.root`
- do not add `compiledFonts.root` as a separate final image `copyToRoot` entry
- keep filesystem permissions owned by `lib/compiler/filesystem.nix`
