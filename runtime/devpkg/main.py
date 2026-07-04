#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


NIXPKGS_REF = os.environ.get("DEVPKG_NIXPKGS_REF", "nixpkgs")
NIXPKGS_CACHE_KEY = os.environ.get("DEVPKG_NIXPKGS_CACHE_KEY", NIXPKGS_REF)
NIX_BIN = os.environ.get("DEVPKG_NIX_BIN", "nix")
NIX_EXPERIMENTAL_FLAGS = [
    "--extra-experimental-features",
    "nix-command",
    "--extra-experimental-features",
    "flakes",
]
CURRENT_SYSTEM = None
CACHE_SCHEMA_VERSION = 1


USAGE = """devpkg add <package>...
devpkg remove <package>...
devpkg list [--json]
devpkg search <query>
devpkg add-lib [--outputs <outputs>] <package>...
devpkg add-lib --raw <installable>...
devpkg remove-lib <package>...
devpkg list-lib [--json]
devpkg add-dev-lib [--outputs <outputs>] <package>...
devpkg add-dev-lib --raw <installable>...
devpkg remove-dev-lib <package>...
devpkg list-dev-lib [--json]
devpkg help

examples:
  devpkg add cowsay
  devpkg remove cowsay
  devpkg list
  devpkg add-lib zlib
  devpkg add-dev-lib openssl
  devpkg add-dev-lib --outputs out,dev,static zlib
  devpkg add-dev-lib --raw 'nixpkgs#openssl^out,dev'
"""


COMMANDS = [
    "add",
    "install",
    "remove",
    "rm",
    "uninstall",
    "list",
    "ls",
    "search",
    "add-lib",
    "remove-lib",
    "list-lib",
    "add-dev-lib",
    "remove-dev-lib",
    "list-dev-lib",
    "help",
    "-h",
    "--help",
]

OUTPUTS = ["out", "dev", "lib", "static", "doc", "man", "debug"]


def usage(file=sys.stdout):
    print(USAGE, end="", file=file)


def die(message: str) -> None:
    print(f"devpkg: {message}", file=sys.stderr)
    raise SystemExit(1)


def nix_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("NIXPKGS_CONFIG", "/etc/nixpkgs/config.nix")
    env.setdefault("NIXPKGS_ALLOW_UNFREE", "1")
    env.setdefault("NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM", "1")
    env.setdefault("NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE", "1")
    return env


def nix_run(args: list[str], *, capture: bool = False, stderr=None) -> subprocess.CompletedProcess:
    kwargs = {
        "env": nix_env(),
        "text": True,
        "stderr": stderr,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        if stderr is None:
            kwargs["stderr"] = subprocess.PIPE
    return subprocess.run([NIX_BIN, *NIX_EXPERIMENTAL_FLAGS, *args], **kwargs)


def nix_check(args: list[str]) -> int:
    return nix_run(args).returncode


def nix_capture(args: list[str], *, stderr=None) -> str:
    result = nix_run(args, capture=True, stderr=stderr)
    if result.returncode != 0:
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        raise SystemExit(result.returncode)
    return result.stdout or ""


def current_system() -> str:
    global CURRENT_SYSTEM
    if CURRENT_SYSTEM is None:
        configured = os.environ.get("DEVPKG_SYSTEM")
        if configured:
            CURRENT_SYSTEM = configured
        else:
            CURRENT_SYSTEM = nix_capture(["eval", "--impure", "--expr", "builtins.currentSystem", "--raw"]).strip()
    return CURRENT_SYSTEM


def default_xdg_cache_home() -> Path:
    xdg_cache_home = os.environ.get("XDG_CACHE_HOME")
    if xdg_cache_home:
        return Path(xdg_cache_home)
    home = os.environ.get("HOME")
    if not home:
        die("HOME or XDG_CACHE_HOME is required")
    return Path(home) / ".cache"


def default_xdg_data_home() -> Path:
    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if xdg_data_home:
        return Path(xdg_data_home)
    home = os.environ.get("HOME")
    if not home:
        die("HOME or XDG_DATA_HOME is required")
    return Path(home) / ".local" / "share"


def devpkg_cache_home() -> Path:
    configured = os.environ.get("DEVPKG_CACHE_HOME")
    if configured:
        return Path(configured)
    return default_xdg_cache_home() / "devpkg"


def runtime_library_profile() -> Path:
    configured = os.environ.get("DEVPKG_RUNTIME_LIBRARY_PROFILE")
    if configured:
        return Path(configured)
    return default_xdg_data_home() / "devpkg" / "runtime-libraries" / "profile"


def build_library_profile() -> Path:
    configured = os.environ.get("DEVPKG_BUILD_LIBRARY_PROFILE")
    if configured:
        return Path(configured)
    return default_xdg_data_home() / "devpkg" / "build-libraries" / "profile"


def normalize_attr(spec: str) -> str:
    if not spec:
        die("package name is required")
    spec = spec.split("^", 1)[0]
    if "#" in spec:
        spec = spec.rsplit("#", 1)[1]
    if spec.startswith("pkgs."):
        spec = spec[len("pkgs.") :]
    system = current_system()
    for prefix in (f"legacyPackages.{system}.", f"packages.{system}."):
        if spec.startswith(prefix):
            spec = spec[len(prefix) :]
    return spec


def installable_for(package: str) -> str:
    return f"{NIXPKGS_REF}#{normalize_attr(package)}"


def installable_for_outputs(attr: str, outputs: str) -> str:
    return f"{NIXPKGS_REF}#{attr}^{outputs}"


def profile_json_text() -> str:
    return nix_capture(["profile", "list", "--json", "--no-pretty"])


def profile_json() -> dict:
    return parse_json_text(profile_json_text(), "nix profile list")


def profile_json_for_text(profile: Path) -> str:
    result = nix_run(
        ["profile", "list", "--profile", str(profile), "--json", "--no-pretty"],
        capture=True,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode == 0:
        return result.stdout or ""
    return '{"elements":{}}\n'


def profile_json_for(profile: Path) -> dict:
    return parse_json_text(profile_json_for_text(profile), f"nix profile list --profile {profile}")


def parse_json_text(text: str, source: str):
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        die(f"invalid JSON from {source}: {exc}")


def package_outputs(attr: str) -> list[str]:
    system = current_system()
    installables = [
        f"{NIXPKGS_REF}#legacyPackages.{system}.{attr}.outputs",
        f"{NIXPKGS_REF}#packages.{system}.{attr}.outputs",
    ]
    for installable in installables:
        result = nix_run(["eval", "--impure", "--json", installable], capture=True, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            continue
        try:
            outputs = json.loads(result.stdout or "null")
        except json.JSONDecodeError:
            continue
        if isinstance(outputs, list) and all(isinstance(output, str) for output in outputs):
            return outputs
    return ["out"]


def runtime_output_from_outputs(outputs: list[str]) -> str:
    if "lib" in outputs:
        return "lib"
    if "out" in outputs:
        return "out"
    if outputs:
        return outputs[0]
    return "out"


def default_outputs_for(mode: str, attr: str) -> str:
    outputs = package_outputs(attr)
    runtime_output = runtime_output_from_outputs(outputs)
    if mode == "runtime":
        return runtime_output
    selected = [runtime_output]
    if "dev" in outputs and runtime_output != "dev":
        selected.append("dev")
    return ",".join(selected)


def normalize_outputs_arg(outputs: str) -> str:
    normalized = outputs.replace(" ", ",").strip(",")
    if not normalized:
        die("--outputs requires at least one output")
    return normalized


def profile_matches(data: dict, requested: str) -> list[str]:
    attr = normalize_attr(requested)
    base = attr.rsplit(".", 1)[-1]
    elements = data.get("elements") or {}
    matches = []
    for key, value in elements.items():
        attr_path = ""
        if isinstance(value, dict):
            attr_path = value.get("attrPath") or ""
        if (
            key == requested
            or key == attr
            or key == base
            or attr_path == attr
            or attr_path.endswith(f".{attr}")
            or attr_path.endswith(f".{base}")
        ):
            matches.append(key)
    return sorted(set(matches))


def resolve_profile_name_from_json(requested: str, data: dict) -> str:
    matches = profile_matches(data, requested)
    if not matches:
        die(f"package not installed: {requested}")
    if len(matches) == 1:
        return matches[0]
    print(f"devpkg: package name is ambiguous: {requested}", file=sys.stderr)
    print("matches:", file=sys.stderr)
    for match in matches:
        print(f"  {match}", file=sys.stderr)
    raise SystemExit(1)


def elements(data: dict) -> dict:
    value = data.get("elements")
    if isinstance(value, dict):
        return value
    return {}


def cmd_add_packages(args: list[str]) -> int:
    if not args:
        usage(sys.stderr)
        return 1
    installables = [installable_for(package) for package in args]
    return nix_check(["profile", "add", "--impure", *installables])


def cmd_remove_packages(args: list[str]) -> int:
    if not args:
        usage(sys.stderr)
        return 1
    data = profile_json()
    removals = [resolve_profile_name_from_json(package, data) for package in args]
    return nix_check(["profile", "remove", *removals])


def cmd_list_packages(args: list[str]) -> int:
    if args == ["--json"]:
        print(profile_json_text(), end="")
        return 0
    if args:
        usage(sys.stderr)
        return 1
    data = profile_json()
    for key, value in sorted(elements(data).items()):
        attr_path = value.get("attrPath") if isinstance(value, dict) else ""
        print(f"{key}\t{attr_path or ''}")
    return 0


def parse_library_args(args: list[str]) -> tuple[bool, str, list[str]]:
    raw = False
    outputs = ""
    specs = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--raw":
            raw = True
            index += 1
        elif arg == "--outputs":
            if index + 1 >= len(args):
                die("--outputs requires a value")
            outputs = normalize_outputs_arg(args[index + 1])
            index += 2
        elif arg.startswith("--outputs="):
            outputs = normalize_outputs_arg(arg.split("=", 1)[1])
            index += 1
        elif arg == "--":
            specs.extend(args[index + 1 :])
            break
        elif arg.startswith("-"):
            die(f"unknown option: {arg}")
        else:
            specs.append(arg)
            index += 1
    return raw, outputs, specs


def cmd_add_libraries(mode: str, profile: Path, args: list[str]) -> int:
    raw, outputs, specs = parse_library_args(args)
    if not specs:
        usage(sys.stderr)
        return 1
    if raw and outputs:
        die("--raw cannot be combined with --outputs")

    installables = []
    for spec in specs:
        if raw:
            installables.append(spec)
            continue
        attr = normalize_attr(spec)
        selected_outputs = outputs or default_outputs_for(mode, attr)
        installables.append(installable_for_outputs(attr, selected_outputs))

    profile.parent.mkdir(parents=True, exist_ok=True)
    return nix_check(["profile", "add", "--impure", "--profile", str(profile), *installables])


def cmd_remove_libraries(profile: Path, args: list[str]) -> int:
    if not args:
        usage(sys.stderr)
        return 1
    data = profile_json_for(profile)
    removals = [resolve_profile_name_from_json(package, data) for package in args]
    return nix_check(["profile", "remove", "--profile", str(profile), *removals])


def cmd_list_libraries(profile: Path, args: list[str]) -> int:
    if args == ["--json"]:
        print(profile_json_for_text(profile), end="")
        return 0
    if args:
        usage(sys.stderr)
        return 1
    data = profile_json_for(profile)
    for key, value in sorted(elements(data).items()):
        attr_path = value.get("attrPath") if isinstance(value, dict) else ""
        outputs = value.get("outputs") if isinstance(value, dict) else []
        if not isinstance(outputs, list):
            outputs = []
        print(f"{key}\t{attr_path or ''}\t{','.join(str(output) for output in outputs)}")
    return 0


def complete_commands(prefix: str) -> None:
    for command in COMMANDS:
        if command.startswith(prefix):
            print(command)


def complete_outputs(prefix: str) -> None:
    for output in OUTPUTS:
        if output.startswith(prefix):
            print(output)


def package_cache_path(parent: str) -> Path:
    cache_id = "\0".join([str(CACHE_SCHEMA_VERSION), NIXPKGS_CACHE_KEY, current_system(), parent])
    digest = hashlib.sha256(cache_id.encode("utf-8")).hexdigest()
    return devpkg_cache_home() / "packages" / f"{digest}.json"


def read_package_cache(parent: str) -> list[str] | None:
    path = package_cache_path(parent)
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    if data.get("schemaVersion") != CACHE_SCHEMA_VERSION:
        return None
    if data.get("nixpkgsCacheKey") != NIXPKGS_CACHE_KEY:
        return None
    if data.get("system") != current_system() or data.get("parent") != parent:
        return None
    attr_names = data.get("attrNames")
    if not isinstance(attr_names, list) or not all(isinstance(name, str) for name in attr_names):
        return None
    return attr_names


def write_package_cache(parent: str, attr_names: list[str]) -> None:
    path = package_cache_path(parent)
    data = {
        "schemaVersion": CACHE_SCHEMA_VERSION,
        "nixpkgsCacheKey": NIXPKGS_CACHE_KEY,
        "system": current_system(),
        "parent": parent,
        "attrNames": attr_names,
    }
    tmp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp_path, path)
    except OSError:
        try:
            tmp_path.unlink()
        except OSError:
            pass


def eval_package_scope(parent: str) -> list[str] | None:
    system = current_system()
    expr = f"""
    let
      ref = {json.dumps(NIXPKGS_REF)};
      parent = {json.dumps(parent)};
      system = {json.dumps(system)};
      flake = builtins.getFlake ref;
      pkgs =
        if flake ? legacyPackages && builtins.hasAttr system flake.legacyPackages then
          flake.legacyPackages.${{system}}
        else
          flake.packages.${{system}};
      parts = builtins.filter (part: builtins.isString part && part != "") (builtins.split "\\\\." parent);
      scope = builtins.foldl'
        (current: name:
          if builtins.isAttrs current && builtins.hasAttr name current then
            builtins.getAttr name current
          else
            {{ }})
        pkgs
        parts;
    in
      if builtins.isAttrs scope then builtins.attrNames scope else [ ]
    """
    result = nix_run(["eval", "--impure", "--json", "--expr", expr], capture=True, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        return None
    try:
        attr_names = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return None
    if isinstance(attr_names, list) and all(isinstance(name, str) for name in attr_names):
        return sorted(set(attr_names))
    return None


def package_scope_names(parent: str) -> list[str] | None:
    cached = read_package_cache(parent)
    if cached is not None:
        return cached
    attr_names = eval_package_scope(parent)
    if attr_names is not None:
        write_package_cache(parent, attr_names)
    return attr_names


def complete_packages(prefix: str) -> None:
    parent = ""
    leaf = prefix
    if "." in prefix:
        parent, leaf = prefix.rsplit(".", 1)
    attr_names = package_scope_names(parent)
    if attr_names is None:
        return
    for name in attr_names:
        if name.startswith(leaf):
            print(name if parent == "" else f"{parent}.{name}")


def complete_installed(mode: str, prefix: str) -> None:
    if mode == "main":
        data = profile_json()
    elif mode == "runtime":
        data = profile_json_for(runtime_library_profile())
    elif mode == "build":
        data = profile_json_for(build_library_profile())
    else:
        die(f"unknown completion profile: {mode}")
    for key in sorted(elements(data)):
        if key.startswith(prefix):
            print(key)


def cmd_complete(args: list[str]) -> int:
    subject = args[0] if args else ""
    rest = args[1:]
    if subject == "commands":
        complete_commands(rest[0] if rest else "")
    elif subject == "packages":
        complete_packages(rest[0] if rest else "")
    elif subject == "installed":
        complete_installed(rest[0] if rest else "", rest[1] if len(rest) > 1 else "")
    elif subject == "outputs":
        complete_outputs(rest[0] if rest else "")
    else:
        die(f"unknown completion subject: {subject}")
    return 0


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    args = argv[1:]
    if cmd in {"add", "install"}:
        return cmd_add_packages(args)
    if cmd in {"remove", "rm", "uninstall"}:
        return cmd_remove_packages(args)
    if cmd in {"list", "ls"}:
        return cmd_list_packages(args)
    if cmd == "search":
        if not args or not args[0]:
            usage(sys.stderr)
            return 1
        return nix_check(["search", "--impure", NIXPKGS_REF, args[0]])
    if cmd == "add-lib":
        return cmd_add_libraries("runtime", runtime_library_profile(), args)
    if cmd == "remove-lib":
        return cmd_remove_libraries(runtime_library_profile(), args)
    if cmd == "list-lib":
        return cmd_list_libraries(runtime_library_profile(), args)
    if cmd == "add-dev-lib":
        return cmd_add_libraries("build", build_library_profile(), args)
    if cmd == "remove-dev-lib":
        return cmd_remove_libraries(build_library_profile(), args)
    if cmd == "list-dev-lib":
        return cmd_list_libraries(build_library_profile(), args)
    if cmd == "complete":
        return cmd_complete(args)
    if cmd in {"help", "-h", "--help", ""}:
        usage()
        return 0
    usage(sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
