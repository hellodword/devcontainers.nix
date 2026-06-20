{
  pkgs,
  lib,
  imageNames,
}:

let
  workflowDir = ../.github/workflows;
  template = ../.github/workflows/_build-image.yml.j2;
  imageNameArray = lib.concatMapStringsSep "\n" (name: "    ${lib.escapeShellArg name}") imageNames;

  generatedWorkflows =
    pkgs.runCommand "generated-workflows"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.minijinja
        ];
      }
      ''
        mkdir -p "$out"
        targets=(
        ${imageNameArray}
        )

        for target in "''${targets[@]}"; do
          minijinja-cli \
            --strict \
            --autoescape none \
            --syntax variable-start='<<' \
            --syntax variable-end='>>' \
            --define image_target="$target" \
            --output "$out/build-image-$target.yml" \
            ${template}
        done
      '';

  generateWorkflows = pkgs.writeShellApplication {
    name = "generate-workflows";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.minijinja
    ];
    text = ''
      workflow_dir=".github/workflows"
      template="$workflow_dir/_build-image.yml.j2"
      mkdir -p "$workflow_dir"
      find "$workflow_dir" -maxdepth 1 -type f -name 'build-image-*.yml' -delete
      test -f "$template"

      targets=(
      ${imageNameArray}
      )

      for target in "''${targets[@]}"; do
        minijinja-cli \
          --strict \
          --autoescape none \
          --syntax variable-start='<<' \
          --syntax variable-end='>>' \
          --define image_target="$target" \
          --output "$workflow_dir/build-image-$target.yml" \
          "$template"
      done
    '';
  };

  generatedWorkflowsCheck =
    pkgs.runCommand "generated-workflows-check"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.diffutils
        ];
      }
      ''
        status=0
        repo_workflow_dir=${workflowDir}

        for generated in ${generatedWorkflows}/build-image-*.yml; do
          name="$(basename "$generated")"
          if [ ! -f "$repo_workflow_dir/$name" ]; then
            echo "missing generated workflow: $name" >&2
            status=1
            continue
          fi
          if ! cmp -s "$generated" "$repo_workflow_dir/$name"; then
            echo "generated workflow out of date: $name" >&2
            diff -u "$generated" "$repo_workflow_dir/$name" || true
            status=1
          fi
        done

        for existing in "$repo_workflow_dir"/build-image-*.yml; do
          [ -e "$existing" ] || continue
          name="$(basename "$existing")"
          if [ ! -f "${generatedWorkflows}/$name" ]; then
            echo "stale generated workflow: $name" >&2
            status=1
          fi
        done

        [ "$status" -eq 0 ]
        touch "$out"
      '';
in
{
  inherit
    generatedWorkflows
    generatedWorkflowsCheck
    generateWorkflows
    ;
}
