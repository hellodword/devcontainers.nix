{
  pkgs,
  lib,
  targets,
}:

let
  registryPrefix = "ghcr.io/hellodword/devcontainers-";
  code = value: "`${value}`";
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  modulePath = target: "images/${builtins.baseNameOf (pathString target.module)}";
  imageRef = target: tag: "${registryPrefix}${target.family}:${tag}";
  targetRefs = target: map (tag: imageRef target tag) target.tags;
  codeList = values: lib.concatStringsSep ", " (map code values);
  tableRefs = target: lib.concatStringsSep "<br>" (map code (targetRefs target));
  docsMetadata = {
    nix = "Use for Nix flakes, Nix modules, shell tooling, and general repositories that still benefit from Python and Node.js runtimes.";
    go = "Use for current Go projects with common Go tools.";
    "go-web" = "Use for Go services that also need web and data tools.";
    nodejs = "Use for Node.js, TypeScript, frontend, and package-manager heavy projects.";
    python3 = "Use for Python projects with uv, pipx, formatters, linters, and test tools.";
    "python3-web" = "Use for Python services that also need web and data tools.";
    rust = "Use for Rust projects with nightly Rust, rust-analyzer, clippy, and cargo helpers.";
    "rust-web" = "Use for Rust services that also need web and data tools.";
    flutter = "Use for Flutter, Dart, Android, and Chromium-backed web workflows.";
  };
  targetUse =
    target:
    docsMetadata.${target.target}
      or (
        if target.family == "go" then
          "Use for the previous Go major/minor line exposed by this repository."
        else if target.family == "nodejs" then
          "Use for the previous even Node.js major line exposed by this repository."
        else
          "Use when you need the ${target.family} image variant published by this target."
      );
  generatedDocs = {
    readmeImageRefs = ''
      ${lib.concatMapStringsSep "\n" (
        target: lib.concatMapStringsSep "\n" (ref: "- ${code ref}") (targetRefs target)
      ) targets.imageTargetList}
    '';

    usageImageRefs = ''
      The flake builds ${toString (builtins.length targets.imageTargetList)} image targets. Target names are used for local Nix outputs, generated workflow names, and smoke plans. Published image references use the `ghcr.io/hellodword/devcontainers-` prefix plus the target's family and tag.

      | Target | Published references | Use when |
      | --- | --- | --- |
      ${lib.concatMapStringsSep "\n" (
        target: "| ${code target.target} | ${tableRefs target} | ${targetUse target} |"
      ) targets.imageTargetList}

      `go`, `nodejs`, and `python3` also publish version tags for their current language line when the target defines one.
    '';

    architectureImageTargets = ''
      | Target | Registry family | Tags | Base module |
      | --- | --- | --- | --- |
      ${lib.concatMapStringsSep "\n" (
        target:
        "| ${code target.target} | ${code "devcontainers-${target.family}"} | ${codeList target.tags} | ${code (modulePath target)} |"
      ) targets.imageTargetList}
    '';
  };

  generatedDocsJson = pkgs.writeText "generated-docs.json" (builtins.toJSON generatedDocs);
  generateDocsScript = pkgs.writeText "generate-docs.py" ''
    import json
    import sys
    from pathlib import Path


    FRAGMENTS = [
        ("README.md", "image-refs", "readmeImageRefs"),
        ("docs/usage.md", "image-refs", "usageImageRefs"),
        ("docs/architecture.md", "image-targets", "architectureImageTargets"),
    ]


    def replace_fragment(path: Path, marker: str, content: str) -> bool:
        begin = f"<!-- BEGIN GENERATED:{marker} -->"
        end = f"<!-- END GENERATED:{marker} -->"
        text = path.read_text(encoding="utf-8")
        before, begin_marker, rest = text.partition(begin)
        if not begin_marker:
            raise SystemExit(f"missing generated block start {begin!r} in {path}")
        current, end_marker, after = rest.partition(end)
        if not end_marker:
            raise SystemExit(f"missing generated block end {end!r} in {path}")
        replacement = f"{begin}\n{content.rstrip()}\n{end}"
        updated = before + replacement + after
        if updated == text:
            return False
        path.write_text(updated, encoding="utf-8")
        return True


    def main(argv: list[str]) -> int:
        if len(argv) != 2:
            print("usage: generate-docs <generated-docs.json>", file=sys.stderr)
            return 2
        data = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        changed = []
        for filename, marker, key in FRAGMENTS:
            if replace_fragment(Path(filename), marker, data[key]):
                changed.append(filename)
        if changed:
            for filename in changed:
                print(f"updated {filename}")
        else:
            print("generated docs already up to date")
        return 0


    if __name__ == "__main__":
        raise SystemExit(main(sys.argv))
  '';

  generateDocs = pkgs.writeShellApplication {
    name = "generate-docs";
    runtimeInputs = [
      pkgs.python3
    ];
    text = ''
      exec python3 ${generateDocsScript} ${generatedDocsJson}
    '';
  };
in
{
  inherit generateDocs;
}
