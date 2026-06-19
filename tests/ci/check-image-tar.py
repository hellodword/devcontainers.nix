#!/usr/bin/env python3
import json
import pathlib
import re
import tarfile
import sys


SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)
SHELL_INIT_AUTORUN_RE = re.compile(r"(?m)\b(?:uvx|npx)\b")


def normalize(name: str) -> str:
    return name.lstrip("./")


def is_shell_init_path(name: str) -> bool:
    return (
        name == "etc/profile"
        or name == "etc/bash.bashrc"
        or name.startswith("etc/profile.d/")
        or name.endswith(".bashrc")
        or name.endswith(".profile")
    )


def fail(message: str):
    print(f"image-tar-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_layer_names(archive: tarfile.TarFile, layer_name: str) -> tuple[set[str], list[str], list[str]]:
    member = archive.getmember(layer_name)
    payload = archive.extractfile(member)
    if payload is None:
        fail(f"missing payload for layer {layer_name}")
    names: set[str] = set()
    suspicious: list[str] = []
    shell_init_autorun: list[str] = []
    with tarfile.open(fileobj=payload, mode="r|*") as layer_tar:
        for layer_member in layer_tar:
            normalized = normalize(layer_member.name)
            names.add(normalized)
            if (
                layer_member.isfile()
                and (
                    normalized.startswith("usr/share/devcontainer/")
                    or normalized == "etc/os-release"
                )
                and layer_member.size <= 1024 * 1024
            ):
                fileobj = layer_tar.extractfile(layer_member)
                if fileobj is None:
                    continue
                text = fileobj.read().decode("utf-8", errors="ignore")
                if SENSITIVE_VALUE_RE.search(text):
                    suspicious.append(normalized)
                if is_shell_init_path(normalized) and SHELL_INIT_AUTORUN_RE.search(text):
                    shell_init_autorun.append(normalized)
    return names, suspicious, shell_init_autorun


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-image-tar.py <oci-tar.gz> <image-name>", file=sys.stderr)
        return 1

    tar_path = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    all_names: set[str] = set()
    suspicious_files: list[str] = []
    shell_init_autorun_files: list[str] = []
    with tarfile.open(tar_path, mode="r:gz") as archive:
        manifest = json.load(archive.extractfile("manifest.json"))
        for layer_name in manifest[0]["Layers"]:
            layer_names, layer_suspicious, layer_shell_init = read_layer_names(archive, layer_name)
            all_names.update(layer_names)
            suspicious_files.extend(layer_suspicious)
            shell_init_autorun_files.extend(layer_shell_init)

    required = [
        "bin/devcontainer-entrypoint",
        "usr/local/bin/devcontainer-entrypoint",
        "usr/share/devcontainer/tasks.json",
        "usr/share/devcontainer/vscode/extensions-index.json",
        "etc/os-release",
        "bin/bash",
        "usr/bin/env",
    ]

    for name in required:
        if name not in all_names:
            fail(f"required path missing: {name}")

    has_vsix = any(name.startswith("usr/share/devcontainer/vscode/vsix/") and name.endswith(".vsix") for name in all_names)
    if not has_vsix:
        fail("no vsix payload found in image tar")

    has_extension_dir = any(
        name.startswith("usr/share/devcontainer/vscode/extensions/") and name.endswith("/package.json")
        for name in all_names
    )
    if not has_extension_dir:
        fail("no unpacked extension package.json found in image tar")

    has_docker_access = "bin/devcontainer-docker-access" in all_names
    if image_name == "nix-dind":
        if not has_docker_access:
            fail("docker access helper missing from nix-dind image")
    else:
        if has_docker_access:
            fail(f"docker access helper must not ship in {image_name}")

    if image_name == "nix":
        if "lib64/ld-linux-x86-64.so.2" not in all_names:
            fail("dynamic loader symlink missing for x86_64 image")

    if suspicious_files:
        fail(f"suspicious secret-like content found in image tar: {', '.join(sorted(set(suspicious_files)))}")
    if shell_init_autorun_files:
        fail(
            "shell init files auto-run uvx or npx: "
            + ", ".join(sorted(set(shell_init_autorun_files)))
        )

    print(f"image-tar-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
