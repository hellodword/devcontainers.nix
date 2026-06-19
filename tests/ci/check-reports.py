#!/usr/bin/env python3
import json
import os
import pathlib
import re
import subprocess
import sys

REQUIRED_REPORT_FILES = {
    "ci-plan.json",
    "closure-report.json",
    "env-report.json",
    "extensions-index.json",
    "extensions-report.json",
    "filesystem-report.json",
    "fhs-runtime-report.json",
    "graph.json",
    "image-plan.json",
    "layer-plan.json",
    "metadata-label.json",
    "metadata-merged-preview.json",
    "metadata-schema-report.json",
    "security-report.json",
    "smoke-test-plan.json",
}

REQUIRED_CI_REPORT_FILES = REQUIRED_REPORT_FILES - {"ci-plan.json"}
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def fail(message: str):
    print(f"report-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-reports.py <reports-dir> <image-name>", file=sys.stderr)
        return 1

    reports_dir = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    missing_reports = sorted(
        report_name for report_name in REQUIRED_REPORT_FILES if not (reports_dir / report_name).is_file()
    )
    if missing_reports:
        fail(f"reports directory missing files: {', '.join(missing_reports)}")

    metadata_label = read_json(reports_dir / "metadata-label.json")
    metadata_preview = read_json(reports_dir / "metadata-merged-preview.json")
    metadata_schema = read_json(reports_dir / "metadata-schema-report.json")
    layer_plan = read_json(reports_dir / "layer-plan.json")
    extensions_report = read_json(reports_dir / "extensions-report.json")
    extensions_index = read_json(reports_dir / "extensions-index.json")
    filesystem_report = read_json(reports_dir / "filesystem-report.json")
    smoke_plan = read_json(reports_dir / "smoke-test-plan.json")
    image_plan = read_json(reports_dir / "image-plan.json")
    security_report = read_json(reports_dir / "security-report.json")
    fhs_runtime_report = read_json(reports_dir / "fhs-runtime-report.json")
    ci_plan = read_json(reports_dir / "ci-plan.json")
    env_report = read_json(reports_dir / "env-report.json")
    preview_container_env = metadata_preview.get("containerEnv") or {}

    if not isinstance(metadata_label, list):
        fail("metadata-label.json must be a JSON array")
    if not metadata_schema["hasRemoteUser"]:
        fail("metadata schema must include remoteUser")
    if not metadata_schema["hasLifecycle"]:
        fail("metadata schema must include lifecycle commands")
    if not metadata_schema["hasVscodeCustomizations"]:
        fail("metadata schema must include VS Code customizations")
    if metadata_schema["hasDockerMetadata"]:
        fail(f"{image_name} metadata must not declare Docker daemon access metadata")

    for report_name in REQUIRED_REPORT_FILES:
        report_data = read_json(reports_dir / report_name)
        for text in walk_strings(report_data):
            if SENSITIVE_VALUE_RE.search(text):
                fail(f"{report_name} appears to contain sensitive material")

    layer_count = len(layer_plan["layers"])
    layer_max = int(layer_plan["budget"]["max"])
    if layer_count > layer_max:
        fail(f"layer count {layer_count} exceeds budget {layer_max}")
    for layer in layer_plan["layers"]:
        if not layer["build"]["copyToRoot"]:
            fail(f"layer {layer['group']} must be buildable as a copyToRoot layer")
        if layer["pathCount"] < 1:
            fail(f"layer {layer['group']} must include at least one store path")

    if not smoke_plan["tests"]:
        fail("smoke-test-plan.json must include at least one test")

    smoke_plan_file = reports_dir / "smoke-test-plan.json"
    smoke_checker = pathlib.Path(
        os.environ.get("CHECK_SMOKE_PLAN", pathlib.Path(__file__).with_name("check-smoke-plan.py"))
    )
    subprocess.run(
        ["python3", str(smoke_checker), str(smoke_plan_file), image_name],
        check=True,
    )

    if image_plan["backend"] != "nix2container":
        fail("image-plan.json must report nix2container backend")
    if image_plan["entrypoint"] != ["/usr/local/bin/devcontainer-entrypoint"]:
        fail("image-plan.json entrypoint mismatch")
    if image_plan["user"] != "vscode":
        fail("image-plan.json must run as vscode")
    if image_plan["workingDir"] != "/workspaces":
        fail("image-plan.json working directory mismatch")

    if not fhs_runtime_report["enabled"]:
        fail("fhs-runtime-report.json must confirm FHS runtime is enabled")
    if fhs_runtime_report.get("dynamicLoaderMode") != "nix-ld":
        fail("fhs-runtime-report.json must confirm nix-ld dynamic loader mode")
    real_glibc_loader = fhs_runtime_report.get("realGlibcLoader")
    if not real_glibc_loader or "glibc" not in real_glibc_loader:
        fail("fhs-runtime-report.json must report the real glibc loader")
    if real_glibc_loader == "/lib64/ld-linux-x86-64.so.2":
        fail("NIX_LD must point at the real glibc loader, not the container interpreter")
    fhs_links = {link["target"]: link["source"] for link in fhs_runtime_report["symlinks"]}
    for required_link in [
        "/lib64/ld-linux-x86-64.so.2",
        "/usr/lib/libc.so.6",
        "/usr/lib/libstdc++.so.6",
    ]:
        if required_link not in fhs_links:
            fail(f"fhs-runtime-report.json missing VS Code runtime link: {required_link}")
    if "glibc" not in fhs_links["/usr/lib/libc.so.6"]:
        fail("libc.so.6 must come from glibc")
    if "gcc" not in fhs_links["/usr/lib/libstdc++.so.6"]:
        fail("libstdc++.so.6 must come from the GCC runtime")
    if "nix-ld" not in fhs_links["/lib64/ld-linux-x86-64.so.2"]:
        fail("container dynamic loader must enter nix-ld")

    if "PATH" not in env_report["containerEnvSources"]:
        fail("env-report.json must include PATH source details")
    if not env_report["containerEnvSources"]["PATH"]["pathEntries"]:
        fail("env-report.json PATH source details must include path entries")
    if not env_report["containerEnvSources"]["EDITOR"]["sources"]:
        fail("env-report.json must include source labels for container env entries")
    if preview_container_env.get("PATH") != env_report["containerEnv"]["PATH"]:
        fail("metadata merged preview must retain the compiled PATH entry")
    if preview_container_env.get("EDITOR") != env_report["containerEnv"]["EDITOR"]:
        fail("metadata merged preview must retain the compiled EDITOR entry")
    if "DOCKER_HOST" in env_report["containerEnv"]:
        fail("container env must not configure DOCKER_HOST by default")
    nix_ld_env = fhs_runtime_report.get("nixLdEnv") or {}
    if env_report["containerEnv"].get("NIX_LD") != real_glibc_loader:
        fail("container env must set NIX_LD to the real glibc loader")
    if preview_container_env.get("NIX_LD") != real_glibc_loader:
        fail("metadata merged preview must retain NIX_LD")
    if env_report["containerEnv"].get("NIX_LD_LIBRARY_PATH") != nix_ld_env.get("NIX_LD_LIBRARY_PATH"):
        fail("container env must retain the compiled NIX_LD_LIBRARY_PATH")
    nix_ld_library_path = env_report["containerEnv"].get("NIX_LD_LIBRARY_PATH", "")
    if "glibc" not in nix_ld_library_path or "gcc" not in nix_ld_library_path:
        fail("NIX_LD_LIBRARY_PATH must include glibc and GCC runtime libraries")
    for env_name in ["NIX_LD", "NIX_LD_LIBRARY_PATH"]:
        if env_name not in env_report["containerEnvSources"]:
            fail(f"env-report.json must include {env_name} source details")
        if "compiler.fhs-runtime.nix-ld" not in env_report["containerEnvSources"][env_name]["sources"]:
            fail(f"{env_name} must be sourced from the FHS runtime compiler")

    if not extensions_report["validation"]["noNetworkDuringProjection"]:
        fail("extensions projection must stay offline")
    if not extensions_report["validation"]["allArtifactsLocked"]:
        fail("extensions-report.json must confirm locked extension artifacts")
    if not extensions_report["validation"]["companionToolsProvidedByNix"]:
        fail("extensions-report.json must confirm companion tools come from Nix")
    for extension in extensions_index["extensions"]:
        if extension["version"] == "pinned":
            fail(f"extensions-index.json must record a real version for {extension['id']}")
        if not extension["source"].startswith("nix-vscode-extensions."):
            fail(f"extensions-index.json must record nix-vscode-extensions source for {extension['id']}")
        if not extension["sourceLock"]["ref"]:
            fail(f"extensions-index.json must record source ref for {extension['id']}")

    user_report = filesystem_report["user"]
    if user_report["name"] != "vscode" or user_report["uid"] != 1000:
        fail("filesystem-report.json must declare vscode uid 1000")
    if user_report["group"] != "vscode" or user_report["gid"] != 1000:
        fail("filesystem-report.json must declare vscode gid 1000")
    if user_report["home"] != "/home/vscode" or user_report["shell"] != "/bin/bash":
        fail("filesystem-report.json must declare the vscode home and shell")
    directory_map = {entry["path"]: entry for entry in filesystem_report["directories"]}
    for required_dir in ["/home/vscode", "/tmp", "/var/tmp", "/run/user/1000", "/workspaces"]:
        if required_dir not in directory_map:
            fail(f"filesystem-report.json missing directory: {required_dir}")
    if directory_map["/tmp"]["mode"] != "1777" or directory_map["/var/tmp"]["mode"] != "1777":
        fail("filesystem-report.json must declare sticky tmp directories")
    if directory_map["/home/vscode"]["owner"] != "vscode:vscode":
        fail("filesystem-report.json must declare vscode home ownership")

    ci_report_files = set(ci_plan["reportFiles"])
    missing_ci_reports = sorted(REQUIRED_CI_REPORT_FILES - ci_report_files)
    if missing_ci_reports:
        fail(f"ci-plan.json missing report files: {', '.join(missing_ci_reports)}")

    if security_report["dockerDaemonBakedIntoImage"]:
        fail("security-report.json must confirm no Docker daemon is baked into the image")
    if security_report["dockerSocketMountedByDefault"]:
        fail("security-report.json must confirm no default Docker socket mount")
    if security_report["dockerHostConfiguredByDefault"]:
        fail("security-report.json must confirm DOCKER_HOST is not configured by default")
    if not security_report["lifecycleLogRedaction"]:
        fail("security-report.json must confirm lifecycle log redaction")
    if not security_report["extensionProjectionLogRedaction"]:
        fail("security-report.json must confirm extension projection log redaction")
    if not security_report["extensionArtifactsLocked"]:
        fail("security-report.json must confirm extension artifacts are locked")
    if not security_report["dynamicPackageFreezeReviewable"]:
        fail("security-report.json must confirm devpkg freeze is reviewable")
    if security_report["uvxAutoRunFromShellInit"]:
        fail("security-report.json must confirm uvx is not auto-run from shell init")
    if security_report["npxAutoRunFromShellInit"]:
        fail("security-report.json must confirm npx is not auto-run from shell init")
    if not security_report["shellInitHasNoSideEffects"]:
        fail("security-report.json must confirm shell init remains side-effect free")

    print(f"report-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
