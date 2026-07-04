#!/usr/bin/env python3
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


FAKE_NIX = r"""import json
import os
import shutil
import sys
from pathlib import Path


STATE_DIR = Path(os.environ["FAKE_NIX_STATE"])
SYSTEM = "x86_64-linux"


def profile_key(profile: str) -> str:
    return profile.replace("/", "_").replace(":", "_")


def state_file(profile: str) -> Path:
    return STATE_DIR / f"{profile_key(profile)}.json"


def ensure_state(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text('{"elements":{}}\n', encoding="utf-8")


def read_state(profile: str) -> dict:
    path = state_file(profile)
    ensure_state(path)
    return json.loads(path.read_text(encoding="utf-8"))


def write_state(profile: str, data: dict) -> None:
    path = state_file(profile)
    ensure_state(path)
    path.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")


def add_installable(profile: str, installable: str) -> None:
    data = read_state(profile)
    spec = installable.split("#", 1)[1] if "#" in installable else installable
    outputs = ["out"]
    if "^" in spec:
        spec, output_text = spec.split("^", 1)
        outputs = [part for part in output_text.split(",") if part]
    key = spec.split(".")[-1]
    data.setdefault("elements", {})[key] = {
        "attrPath": f"legacyPackages.{SYSTEM}.{spec}",
        "outputs": outputs,
    }
    write_state(profile, data)

    if profile != "main":
        profile_path = Path(profile)
        if any(output in outputs for output in ("out", "lib")):
            (profile_path / "lib").mkdir(parents=True, exist_ok=True)
            (profile_path / "lib" / "libz.so").touch()
        if "dev" in outputs:
            (profile_path / "include").mkdir(parents=True, exist_ok=True)
            (profile_path / "include" / "zlib.h").touch()


def remove_element(profile: str, name: str) -> None:
    data = read_state(profile)
    data.setdefault("elements", {}).pop(name, None)
    write_state(profile, data)
    if profile != "main" and not data["elements"]:
        shutil.rmtree(Path(profile) / "lib", ignore_errors=True)
        shutil.rmtree(Path(profile) / "include", ignore_errors=True)


def parse_profile_args(args: list[str]) -> tuple[str, list[str]]:
    profile = "main"
    rest = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in {"--impure", "--json", "--no-pretty"}:
            index += 1
        elif arg == "--profile":
            profile = args[index + 1]
            index += 2
        else:
            rest.append(arg)
            index += 1
    return profile, rest


def strip_global_args(args: list[str]) -> list[str]:
    stripped = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--extra-experimental-features":
            index += 2
        else:
            stripped.extend(args[index:])
            break
    return stripped


def main(argv: list[str]) -> int:
    argv = strip_global_args(argv)
    cmd = argv[0] if argv else ""
    args = argv[1:]
    if cmd == "eval":
        joined = " ".join(args)
        if joined == "--impure --expr builtins.currentSystem --raw":
            print(SYSTEM)
            return 0
        if "builtins.attrNames scope" in joined:
            if os.environ.get("FAKE_NIX_DISABLE_PACKAGE_COMPLETION") == "1":
                print("fake nix package completion disabled", file=sys.stderr)
                return 1
            eval_log = os.environ.get("FAKE_NIX_EVAL_LOG")
            if eval_log:
                Path(eval_log).parent.mkdir(parents=True, exist_ok=True)
                with Path(eval_log).open("a", encoding="utf-8") as handle:
                    handle.write(joined + "\n")
            if 'parent = "python3Packages";' in joined:
                print(json.dumps(["black", "debugpy"]))
            else:
                print(json.dumps(["cowsay", "curl", "python3Packages", "zlib"]))
            return 0
        if ".zlib.outputs" in joined:
            print('["out","dev"]')
            return 0
        print(f"fake nix eval unsupported: {joined}", file=sys.stderr)
        return 1
    if cmd == "profile":
        subcmd = args[0] if args else ""
        profile, rest = parse_profile_args(args[1:])
        if subcmd == "add":
            for installable in rest:
                add_installable(profile, installable)
            return 0
        if subcmd == "list":
            print(json.dumps(read_state(profile), sort_keys=True))
            return 0
        if subcmd == "remove":
            for name in rest:
                remove_element(profile, name)
            return 0
        print(f"fake nix profile unsupported subcommand: {subcmd}", file=sys.stderr)
        return 1
    if cmd == "search":
        return 0
    print(f"fake nix unsupported command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
"""


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], *, env: dict[str, str] | None = None, cwd: Path | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(command, env=env, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        fail(
            "command failed: "
            + " ".join(command)
            + f"\nexit={result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def run_stdout(command: list[str], *, env: dict[str, str]) -> str:
    return run(command, env=env).stdout


def require_regex(pattern: str, text: str, label: str) -> None:
    if not re.search(pattern, text, re.MULTILINE):
        fail(f"missing pattern {pattern!r} in {label}\n{text}")


def write_fake_nix(tmpdir: Path) -> Path:
    fake_nix = tmpdir / "fake-nix" / "bin" / "nix"
    fake_nix.parent.mkdir(parents=True)
    fake_nix.write_text(f"#!{sys.executable}\n{FAKE_NIX}", encoding="utf-8")
    fake_nix.chmod(fake_nix.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return fake_nix


def main() -> int:
    devpkg_root = os.environ.get("DEVCONTAINER_DEVPKG")
    if not devpkg_root:
        fail("DEVCONTAINER_DEVPKG is required")
    devpkg = Path(devpkg_root) / "bin" / "devpkg"

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        fake_nix_state = tmpdir / "fake-nix-state"
        fake_nix_state.mkdir()
        fake_nix = write_fake_nix(tmpdir)

        completion_file = Path(devpkg_root) / "share" / "bash-completion" / "completions" / "devpkg"
        if not completion_file.is_file():
            fail(f"completion file missing: {completion_file}")

        base_env = os.environ.copy()
        base_env.update(
            {
                "NIX_CONFIG": os.environ.get("NIX_CONFIG", "experimental-features = nix-command flakes"),
                "FAKE_NIX_STATE": str(fake_nix_state),
                "DEVPKG_NIXPKGS_REF": os.environ.get("DEVPKG_NIXPKGS_REF", "path:/fake-nixpkgs"),
            }
        )

        require_regex("^add$", run_stdout([str(devpkg), "complete", "commands", "ad"], env=base_env), "commands completion")
        require_regex("^dev$", run_stdout([str(devpkg), "complete", "outputs", "d"], env=base_env), "outputs completion")

        project_root = tmpdir / "project"
        env = base_env.copy()
        env.update(
            {
                "HOME": str(project_root / "home"),
                "XDG_CONFIG_HOME": str(project_root / "config"),
                "XDG_CACHE_HOME": str(project_root / "cache"),
                "XDG_DATA_HOME": str(project_root / "data"),
                "XDG_STATE_HOME": str(project_root / "state"),
                "DEVPKG_RUNTIME_LIBRARY_PROFILE": str(project_root / "runtime-libraries" / "profile"),
                "DEVPKG_BUILD_LIBRARY_PROFILE": str(project_root / "build-libraries" / "profile"),
                "DEVPKG_NIX_BIN": str(fake_nix),
                "DEVPKG_NIXPKGS_CACHE_KEY": "fake-nixpkgs-rev",
                "DEVPKG_SYSTEM": "x86_64-linux",
                "FAKE_NIX_EVAL_LOG": str(project_root / "fake-nix-eval.log"),
            }
        )
        for key in ["HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"]:
            Path(env[key]).mkdir(parents=True, exist_ok=True)
        env["PATH"] = f"{env['HOME']}/.nix-profile/bin:{env['XDG_DATA_HOME']}/nix-profile/bin:{env.get('PATH', '')}"

        require_regex("^cowsay$", run_stdout([str(devpkg), "complete", "packages", "cow"], env=env), "package completion")
        require_regex(
            "^python3Packages.black$",
            run_stdout([str(devpkg), "complete", "packages", "python3Packages.bl"], env=env),
            "package scope completion",
        )
        package_cache_dir = Path(env["XDG_CACHE_HOME"]) / "devpkg" / "packages"
        if len(list(package_cache_dir.glob("*.json"))) < 2:
            fail("expected package completion cache files")
        cached_env = env.copy()
        cached_env["FAKE_NIX_DISABLE_PACKAGE_COMPLETION"] = "1"
        require_regex(
            "^cowsay$",
            run_stdout([str(devpkg), "complete", "packages", "cow"], env=cached_env),
            "cached package completion",
        )
        invalidated_env = cached_env.copy()
        invalidated_env["DEVPKG_NIXPKGS_CACHE_KEY"] = "fake-nixpkgs-other-rev"
        if run_stdout([str(devpkg), "complete", "packages", "cow"], env=invalidated_env):
            fail("package completion cache must be invalidated by nixpkgs cache key")

        run([str(devpkg), "add", "cowsay"], env=env)
        package_list = run_stdout([str(devpkg), "list"], env=env)
        require_regex(r"^cowsay\s", package_list, "devpkg list")
        require_regex(r"legacyPackages\..*\.cowsay$", package_list, "devpkg list attr")
        require_regex("^cowsay$", run_stdout([str(devpkg), "complete", "installed", "main", "cow"], env=env), "installed completion")
        run([str(devpkg), "remove", "cowsay"], env=env)
        if run_stdout([str(devpkg), "list"], env=env):
            fail("expected main profile to be empty after remove")

        run([str(devpkg), "add-lib", "zlib"], env=env)
        runtime_list = run_stdout([str(devpkg), "list-lib"], env=env)
        require_regex(r"^zlib\s", runtime_list, "runtime library list")
        require_regex(r"legacyPackages\..*\.zlib", runtime_list, "runtime library attr")
        require_regex("^zlib$", run_stdout([str(devpkg), "complete", "installed", "runtime", "zl"], env=env), "runtime completion")
        if not (Path(env["DEVPKG_RUNTIME_LIBRARY_PROFILE"]) / "lib" / "libz.so").exists():
            fail("runtime library output missing")
        if (Path(env["DEVPKG_RUNTIME_LIBRARY_PROFILE"]) / "include" / "zlib.h").exists():
            fail("runtime library should not include dev output")
        run([str(devpkg), "remove-lib", "zlib"], env=env)
        if run_stdout([str(devpkg), "list-lib"], env=env):
            fail("expected runtime library profile to be empty")

        run([str(devpkg), "add-dev-lib", "zlib"], env=env)
        build_list = run_stdout([str(devpkg), "list-dev-lib"], env=env)
        require_regex(r"^zlib\s", build_list, "build library list")
        require_regex(r"legacyPackages\..*\.zlib", build_list, "build library attr")
        require_regex(r"out,dev", build_list, "build library outputs")
        require_regex("^zlib$", run_stdout([str(devpkg), "complete", "installed", "build", "zl"], env=env), "build completion")
        if not (Path(env["DEVPKG_BUILD_LIBRARY_PROFILE"]) / "lib" / "libz.so").exists():
            fail("build library runtime output missing")
        if not (Path(env["DEVPKG_BUILD_LIBRARY_PROFILE"]) / "include" / "zlib.h").exists():
            fail("build library dev output missing")
        run([str(devpkg), "remove-dev-lib", "zlib"], env=env)
        if run_stdout([str(devpkg), "list-dev-lib"], env=env):
            fail("expected build library profile to be empty")

        run([str(devpkg), "add-dev-lib", "--outputs", "out,dev", "zlib"], env=env)
        if not (Path(env["DEVPKG_BUILD_LIBRARY_PROFILE"]) / "include" / "zlib.h").exists():
            fail("explicit outputs did not install dev files")
        run([str(devpkg), "remove-dev-lib", "zlib"], env=env)

        run([str(devpkg), "add-dev-lib", "--raw", f"{env['DEVPKG_NIXPKGS_REF']}#zlib^out,dev"], env=env)
        if not (Path(env["DEVPKG_BUILD_LIBRARY_PROFILE"]) / "include" / "zlib.h").exists():
            fail("raw installable did not install dev files")
        run([str(devpkg), "remove-dev-lib", "zlib"], env=env)

    print("devpkg-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
