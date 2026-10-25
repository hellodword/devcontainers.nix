#!/usr/bin/env python3
"""Run only in a disposable container: includes real store optimisation and GC."""
import json
import os
import subprocess
from pathlib import Path


def run(*args: str) -> str:
    result = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        # Keep Nix warnings out of JSON and store-path output.
        stderr=None,
        timeout=90,
    )
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}):\n{result.stdout}")
    return result.stdout


def expression(name: str, bash: Path, coreutils: Path) -> str:
    # Refer only to already registered image paths; this test needs no network.
    script = (
        '"${coreutils}/bin/mkdir" -p "$out/bin"; '
        "printf '%s\\n' '#!${bash}/bin/bash' 'printf \"%s\\n\" runtime-profile-ok' > \"$out/bin/runtime-probe\"; "
        '"${coreutils}/bin/chmod" +x "$out/bin/runtime-probe"; '
        'printf "%4096s" runtime-optimiser-probe > "$out/identical"'
    )
    return (
        f"let bash = builtins.storePath {json.dumps(str(bash))}; "
        f"coreutils = builtins.storePath {json.dumps(str(coreutils))}; "
        "in builtins.derivation { "
        f"name = {json.dumps(name)}; system = builtins.currentSystem; "
        'builder = "${bash}/bin/bash"; args = [ "-c" '
        + json.dumps(script) + " ]; }"
    )


def main() -> None:
    bash = Path("/usr/bin/bash").resolve().parent.parent
    coreutils = Path("/usr/bin/mkdir").resolve().parent.parent
    # Include tools unrelated to this derivation or live processes, so GC must
    # retain them through the image roots rather than the active test profile.
    preserved = [Path(f"/usr/bin/{name}").resolve() for name in ["nix", "git", "getent"]]
    config = json.loads(run("nix", "config", "show", "--json"))
    assert config["sandbox"]["value"] is True
    profile = Path(os.environ["XDG_STATE_HOME"]) / "nix/profiles/runtime-smoke"
    profile.parent.mkdir(parents=True, exist_ok=True)

    args = ["--offline", "--impure", "--option", "auto-optimise-store", "true"]
    run("nix", "profile", "install", "--profile", str(profile), *args, "--expr", expression("runtime-profile-probe", bash, coreutils))
    assert "runtime-profile-ok" in run(str(profile / "bin/runtime-probe"))
    output = Path(run("nix", "build", *args, "--no-link", "--print-out-paths", "--expr", expression("runtime-build-probe", bash, coreutils)).strip().splitlines()[-1])
    assert (output / "identical").stat().st_nlink >= 2
    links = Path("/nix/store/.links")
    assert links.stat().st_uid == os.getuid() and os.access(links, os.W_OK)
    run("nix-store", "--gc")
    assert not output.exists(), "unrooted test build must be collected"
    assert all(path.exists() for path in preserved)
    assert "runtime-profile-ok" in run(str(profile / "bin/runtime-probe"))
    print("Nix profile, build, optimiser, GC and image roots: ok")


if __name__ == "__main__":
    main()
