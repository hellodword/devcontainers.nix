{
  pkgs,
  nixpkgs,
  self',
}:
(builtins.listToAttrs (
  map (x: {
    name = "${x}";
    value =
      let
        program = pkgs.writeShellApplication {
          name = "exe";
          text = ''
            ${
              if builtins.hasAttr "copyToDockerDaemon" self'.packages.${x} then
                "nix run .#${x}.copyToDockerDaemon"
              else if builtins.match ".+\.tar\.gz$" (self'.packages.${x}.meta.name or "") == null then
                "nix build .#${x} && ./result | docker image load"
              else
                "nix build .#${x} && docker load < result"
            }
          '';
        };
      in
      {
        type = "app";
        program = "${nixpkgs.lib.getExe program}";
      };
  }) (builtins.attrNames self'.packages)
))
// {
  generate-github-actions = {
    type = "app";
    program = pkgs.writeShellApplication {
      name = "exe";
      runtimeInputs = with pkgs; [
        coreutils
        minijinja
        jq
      ];
      text = ''
        rm -rf .github/workflows/build-image-*.yml

        IFS=" " read -r -a packages_amd64 <<< "$(nix eval --json $".#packages.x86_64-linux" --apply 'x: builtins.concatStringsSep " " (builtins.attrNames x)' | jq -r)"
        IFS=" " read -r -a packages_arm64 <<< "$(nix eval --json $".#packages.aarch64-linux" --apply 'x: builtins.concatStringsSep " " (builtins.attrNames x)' | jq -r)"

        for package in "${"$"}{packages_amd64[@]}"; do
          found=false
          for arm64_package in "${"$"}{packages_arm64[@]}"; do
            if [[ "$package" == "$arm64_package" ]]; then
              found=true
              break
            fi
          done

          args=()

          if $found; then
            args+=(-D systems="x86_64-linux,aarch64-linux")
          else
            args+=(-D systems="x86_64-linux")
          fi

          minijinja-cli .github/workflows/build-image.yml.j2 -D package="$package" -a none "${"$"}{args[@]}" | tee ".github/workflows/build-image-$package.yml"
        done

        for package in "${"$"}{packages_arm64[@]}"; do
          found=false
          for amd64_package in "${"$"}{packages_amd64[@]}"; do
            if [[ "$package" == "$amd64_package" ]]; then
              found=true
              break
            fi
          done

          if ! $found; then
            minijinja-cli .github/workflows/build-image.yml.j2 -D package="$package" -a none -D systems="aarch64-linux" | tee ".github/workflows/build-image-$package.yml"
          fi
        done
      '';
    };
  };
}
