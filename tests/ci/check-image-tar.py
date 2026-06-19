#!/usr/bin/env python3
import io
import json
import tarfile
import pathlib
import sys


def normalize(name: str) -> str:
    return name.lstrip("./")


def fail(message: str):
    print(f"image-tar-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_layer_names(archive: tarfile.TarFile, layer_name: str) -> set[str]:
    member = archive.getmember(layer_name)
    payload = archive.extractfile(member)
    if payload is None:
        fail(f"missing payload for layer {layer_name}")
    data = payload.read()
    names: set[str] = set()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as layer_tar:
        for layer_member in layer_tar.getmembers():
            names.add(normalize(layer_member.name))
    return names


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-image-tar.py <oci-tar.gz> <image-name>", file=sys.stderr)
        return 1

    tar_path = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    all_names: set[str] = set()
    with tarfile.open(tar_path, mode="r:gz") as archive:
        manifest = json.load(archive.extractfile("manifest.json"))
        for layer_name in manifest[0]["Layers"]:
            all_names.update(read_layer_names(archive, layer_name))

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

    if image_name == "nix":
        if "lib64/ld-linux-x86-64.so.2" not in all_names:
            fail("dynamic loader symlink missing for x86_64 image")

    print(f"image-tar-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
