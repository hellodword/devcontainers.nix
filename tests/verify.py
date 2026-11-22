#!/usr/bin/env python3
"""Master verification entrypoint (`nix run .#verify`): static checks, OCI layout, release state machine, and VM suites."""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path


def log_step(title: str) -> None:
    print(f"\n==> {title}", flush=True)


def run_checked(cmd: list[str], *, cwd: Path) -> str:
    print("  $", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)
    return ""


def capture_checked(cmd: list[str], *, cwd: Path) -> str:
    print("  $", " ".join(cmd), flush=True)
    return subprocess.check_output(cmd, cwd=cwd, text=True).strip()


def write_bridge_request(bridge_dir: Path, seq: str, payload: dict) -> Path:
    bridge_dir.mkdir(parents=True, exist_ok=True)
    req_path = bridge_dir / f"{seq}.req.json"
    resp_path = bridge_dir / f"{seq}.resp.json"
    resp_path.unlink(missing_ok=True)
    tmp = bridge_dir / f".{seq}.req.json.tmp"
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    tmp.replace(req_path)
    return resp_path


def wait_bridge_response(resp_path: Path, timeout: int = 3600) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if resp_path.is_file():
            return json.loads(resp_path.read_text(encoding="utf-8"))
        time.sleep(0.5)
    raise RuntimeError(f"Timed out waiting for MCP bridge response {resp_path}")


def run_vm_suite_via_bridge(
    project_dir: Path,
    attr: str,
    bridge_dir: Path,
    cache_dir: Path | None,
    timeout_seconds: int,
) -> None:
    run_token = uuid.uuid4().hex[:10]
    upload_req_id = f"verify-{attr}-upload-{run_token}"
    job_req_id = f"verify-{attr}-job-{run_token}"

    resp_upload = wait_bridge_response(
        write_bridge_request(
            bridge_dir,
            f"{attr}-01-upload",
            {
                "action": "upload_create",
                "request_id": upload_req_id,
                "kind": "cache",
            },
        ),
        timeout=600,
    )
    upload_id = resp_upload["upload_id"]
    upload_url = resp_upload["upload_url"]

    with tempfile.TemporaryDirectory(prefix=f"verify-{attr}-") as work_tmp:
        submit_cmd = [
            "vm-test-submit",
            "--test",
            f".#checks.x86_64-linux.{attr}",
            "--request-id",
            job_req_id,
            "--upload-id",
            upload_id,
            "--upload-url",
            upload_url,
            "--work-dir",
            work_tmp,
            "--timeout-seconds",
            str(timeout_seconds),
        ]
        if cache_dir is not None:
            cache_dir.mkdir(parents=True, exist_ok=True)
            submit_cmd.extend(["--cache-dir", str(cache_dir)])
        run_checked(submit_cmd, cwd=project_dir)

    resp_job = wait_bridge_response(
        write_bridge_request(
            bridge_dir,
            f"{attr}-02-job",
            {
                "action": "nix_job_create",
                "request_id": job_req_id,
                "upload_id": upload_id,
                "timeout_seconds": timeout_seconds,
            },
        ),
        timeout=timeout_seconds + 600,
    )
    conclusion = (resp_job.get("result") or {}).get("conclusion")
    outcome = ((resp_job.get("execution") or {}).get("test") or {}).get("outcome")
    res_state = (resp_job.get("resources") or {}).get("state")
    if conclusion != "passed" or outcome != "passed" or res_state != "released":
        raise RuntimeError(
            f"Remote VM check {attr} did not pass cleanly with released resources: "
            f"conclusion={conclusion!r}, outcome={outcome!r}, resources.state={res_state!r}"
        )
    print(
        f"  Remote VM check {attr} PASSED (job_id={resp_job.get('id')}, resources={res_state})",
        flush=True,
    )


def run_vm_suites(project_dir: Path, timeout_seconds: int) -> None:
    vm_attrs = ("vm-containers", "vm-editor")
    log_step("Building NixOS VM test drivers")
    run_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--no-update-lock-file",
            *[f".#checks.x86_64-linux.{name}.driver" for name in vm_attrs],
        ],
        cwd=project_dir,
    )

    if os.access("/dev/kvm", os.R_OK | os.W_OK):
        for name in vm_attrs:
            log_step(f"Running {name} on local KVM")
            run_checked(
                [
                    "nix",
                    "build",
                    "--no-link",
                    "--print-build-logs",
                    "--no-update-lock-file",
                    f".#checks.x86_64-linux.{name}",
                ],
                cwd=project_dir,
            )
        return

    if submit_cfg := os.environ.get("VM_TEST_SUBMIT_CONFIG"):
        cache_env = os.environ.get("VM_TEST_CACHE_DIR")
        for name in vm_attrs:
            log_step(f"Running {name} via vm-test-submit ({submit_cfg})")
            with tempfile.TemporaryDirectory(prefix=f"verify-{name}-") as work_tmp:
                cmd = [
                    "vm-test-submit",
                    "--config",
                    submit_cfg,
                    "--test",
                    f".#checks.x86_64-linux.{name}",
                    "--work-dir",
                    work_tmp,
                    "--timeout-seconds",
                    str(timeout_seconds),
                ]
                if cache_env:
                    cmd.extend(["--cache-dir", cache_env])
                run_checked(cmd, cwd=project_dir)
        return

    if bridge_env := os.environ.get("VM_TEST_MCP_BRIDGE_DIR"):
        cache_dir = (
            Path(os.environ["VM_TEST_CACHE_DIR"])
            if os.environ.get("VM_TEST_CACHE_DIR")
            else None
        )
        bridge_dir = Path(bridge_env).resolve()
        for name in vm_attrs:
            log_step(f"Running {name} via vm-test-mcp executor")
            run_vm_suite_via_bridge(
                project_dir, name, bridge_dir, cache_dir, timeout_seconds
            )
        return

    raise RuntimeError(
        "KVM is unavailable (/dev/kvm not accessible) and neither VM_TEST_SUBMIT_CONFIG nor "
        "VM_TEST_MCP_BRIDGE_DIR is set; refusing to skip VM acceptance suites."
    )


def verify_workflow_contracts(wf_files: list[str]) -> None:
    cmd_re = re.compile(
        r"(?P<cmd>(?:docker\s+exec|container\.sh)(?:[^\n\\]|\\\s*\n)*?<<[-~]?['\"]?[A-Za-z_0-9]+['\"]?)"
    )
    concurrency_groups: set[str] = set()
    for wf in wf_files:
        text = Path(wf).read_text(encoding="utf-8")
        group_match = re.search(r"(?m)^concurrency:\s*\n\s*group:\s*(\S+)", text)
        if not group_match:
            raise RuntimeError(f"Workflow {wf} is missing top-level concurrency.group")
        concurrency_groups.add(group_match.group(1))
        for match in cmd_re.finditer(text):
            snippet = match.group("cmd")
            tokens = snippet.replace("\\\n", " ").split()
            has_interactive = (
                "-i" in tokens
                or "--interactive" in tokens
                or any(
                    t.startswith("-") and not t.startswith("--") and "i" in t[1:]
                    for t in tokens
                )
            )
            if not has_interactive:
                raise RuntimeError(
                    f"Missing -i on heredoc container invocation in {wf}:\n{snippet}"
                )
    if concurrency_groups != {"devcontainers-pipeline"}:
        raise RuntimeError(
            f"Expected unified workflow concurrency group 'devcontainers-pipeline', got {sorted(concurrency_groups)}"
        )


def verify_manifest_and_cache_exclusions(project_dir: Path, nix_ci: str) -> None:
    expected_unfree = json.loads(
        capture_checked(
            [
                "nix",
                "eval",
                "--no-update-lock-file",
                "--impure",
                "--json",
                "--expr",
                f"""
                let
                  f = builtins.getFlake ("git+file://" + {json.dumps(str(project_dir))});
                  sys = "x86_64-linux";
                  imgs = f.lib.${{sys}}.images;
                  vmNode = f.checks.${{sys}}.vm-editor.nodes.machine;
                  vscodeWrapped = builtins.head (
                    builtins.filter (p: builtins.match ".*vscode.*" (p.name or "") != null)
                      vmNode.environment.systemPackages
                  );
                  tmpRules = vmNode.systemd.tmpfiles.rules;
                  archiveRule = builtins.head (
                    builtins.filter (r: builtins.match ".*vscode-server-linux-.*\\.tar\\.gz.*" r != null) tmpRules
                  );
                  parts = builtins.filter builtins.isString (builtins.split "[[:space:]]+" archiveRule);
                  archivePath = builtins.elemAt parts (builtins.length parts - 1);
                  pkgs = f.inputs.nixpkgs.legacyPackages.${{sys}};
                in
                  (map toString imgs.agents.restrictedPackages)
                  ++ (map toString imgs.editor.restrictedPackages)
                  ++ [
                    (toString pkgs.vscode)
                    (toString pkgs.vscode.vscodeServer)
                    (toString vscodeWrapped)
                    archivePath
                  ]
                """,
            ],
            cwd=project_dir,
        )
    )

    ci_wrapper = Path(nix_ci).resolve().read_text(encoding="utf-8")
    exec_match = re.search(
        r'^exec\s+(?P<py>/\S+)\s+"(?P<ci>/[^"]+)"',
        ci_wrapper,
        re.MULTILINE,
    )
    if not exec_match:
        raise RuntimeError(
            f"Unable to locate python interpreter and ci package in {nix_ci}"
        )
    ci_python = exec_match.group("py")
    ci_pkg_dir = exec_match.group("ci")

    for select_json in ("{}", '{"cacheOnly":true}'):
        with tempfile.TemporaryDirectory(prefix="devcontainers-verify-ci-") as ci_state:
            run_checked(
                [
                    nix_ci,
                    "evaluate",
                    "--project-dir",
                    str(project_dir),
                    "--select",
                    select_json,
                    "--state",
                    ci_state,
                ],
                cwd=project_dir,
            )
            manifest = json.loads(
                (Path(ci_state) / "manifest.json").read_text(encoding="utf-8")
            )
            build_names = {item["name"] for item in manifest["builds"]["build"]}
            for required_driver in ("vm-containers-driver", "vm-editor-driver"):
                if required_driver not in build_names:
                    raise RuntimeError(
                        f"Manifest (select={select_json}) missing {required_driver} in build group: {sorted(build_names)}"
                    )
            if len(manifest["cache"]["bundles"]) < 5:
                raise RuntimeError(
                    f"Manifest (select={select_json}) missing VM bundles: {manifest['cache']['bundles']}"
                )
            excluded_raw = capture_checked(
                [
                    ci_python,
                    "-c",
                    (
                        "import json, sys; from pathlib import Path; "
                        "sys.path.insert(0, sys.argv[1]); import cache; "
                        "manifest = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8')); "
                        "inv = cache.prepare_inventory(manifest); "
                        "print(json.dumps(inv['excluded']))"
                    ),
                    ci_pkg_dir,
                    str(Path(ci_state) / "manifest.json"),
                ],
                cwd=project_dir,
            )
            excluded_set = set(json.loads(excluded_raw))
            leaked = [p for p in expected_unfree if p not in excluded_set]
            if leaked:
                raise RuntimeError(
                    f"Restricted unfree store paths leaked outside excluded inventory (select={select_json}): {leaked}"
                )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="Repository root directory (defaults to current working directory)",
    )
    parser.add_argument(
        "--vm-timeout-seconds",
        type=int,
        default=2400,
        help="Per-suite timeout in seconds for VM checks",
    )
    args = parser.parse_args(argv)

    cwd = Path.cwd().resolve()
    default_root = (
        cwd if (cwd / "flake.nix").is_file() else Path(__file__).resolve().parent.parent
    )
    project_dir = (args.project_dir or default_root).resolve()

    log_step("1. Evaluating flake outputs and formatting check")
    run_checked(
        ["nix", "flake", "check", "--no-build", "--no-update-lock-file"],
        cwd=project_dir,
    )
    run_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--no-update-lock-file",
            ".#checks.x86_64-linux.formatting",
        ],
        cwd=project_dir,
    )

    log_step("2. Running Python, Shell, GitHub Actions, and CI manifest checks")
    py_files = sorted(
        [
            *glob.glob(str(project_dir / "scripts" / "*.py")),
            *glob.glob(str(project_dir / "tests" / "*.py")),
            *glob.glob(str(project_dir / "runtime" / "*" / "*.py")),
        ]
    )
    sh_files = sorted(
        [
            *glob.glob(str(project_dir / "scripts" / "*.sh")),
            str(project_dir / "runtime" / "devcontainer-gui-env" / "main.sh"),
        ]
    )
    wf_files = sorted(glob.glob(str(project_dir / ".github" / "workflows" / "*.yml")))
    run_checked(["ruff", "check", *py_files], cwd=project_dir)
    run_checked(["shellcheck", *sh_files], cwd=project_dir)
    run_checked(["actionlint", *wf_files], cwd=project_dir)
    verify_workflow_contracts(wf_files)

    nix_ci = shutil.which("nix-ci")
    if not nix_ci:
        raise RuntimeError("nix-ci binary not found in PATH")
    verify_manifest_and_cache_exclusions(project_dir, nix_ci)

    log_step("3. Building shared packages.oci and verifying OCI layout invariants")
    oci_out = capture_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--print-out-paths",
            "--no-update-lock-file",
            ".#oci",
        ],
        cwd=project_dir,
    )
    run_checked(
        [sys.executable, str(project_dir / "tests" / "check_oci_layout.py"), oci_out],
        cwd=project_dir,
    )

    log_step(
        "4. Running Workflow 3: digest-preserving release, recovery, and PR update state machine"
    )
    run_checked(
        [
            sys.executable,
            str(project_dir / "tests" / "check_publish.py"),
            "--oci-dir",
            oci_out,
        ],
        cwd=project_dir,
    )

    log_step("5. Running Workflow 1 (vm-containers) and Workflow 2 (vm-editor)")
    run_vm_suites(project_dir, args.vm_timeout_seconds)

    print("\nVERIFY_ALL_PASSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
