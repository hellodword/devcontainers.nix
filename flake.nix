{
  description = "Devcontainer Nix/OCI image compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      lib = pkgs.lib;
      compiler = import ./lib {
        inherit self pkgs lib system;
      };
      imageModules = {
        nix = ./images/nix.nix;
        nix-dind = ./images/nix-dind.nix;
        python = ./images/python.nix;
        nodejs = ./images/nodejs.nix;
        go = ./images/go.nix;
        rust = ./images/rust.nix;
        python-web = ./images/python-web.nix;
        go-web = ./images/go-web.nix;
        rust-web = ./images/rust-web.nix;
        flutter = ./images/flutter.nix;
      };
      images = lib.mapAttrs (_: module: compiler.mkImage { inherit module; }) imageModules;
      reportChecks =
        lib.mapAttrs'
          (name: image:
            lib.nameValuePair
            "reports-${lib.replaceStrings [ "-" ] [ "_" ] name}"
            (pkgs.runCommand "reports-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              export CHECK_SMOKE_PLAN=${./tests/ci/check-smoke-plan.py}
              python3 ${./tests/ci/check-reports.py} ${image.reports} ${name}
              touch "$out"
            ''))
          images;
      reportCliChecks =
        lib.mapAttrs'
          (name: image:
            lib.nameValuePair
            "report-cli-${lib.replaceStrings [ "-" ] [ "_" ] name}"
            (pkgs.runCommand "report-cli-${name}" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq ]; } ''
              bash ${./tests/ci/check-report-cli.sh} ${compiler.runtimePackages."devcontainer-image"} ${image.reports} ${name}
              touch "$out"
            ''))
          images;
      ociLayoutChecks =
        lib.mapAttrs'
          (name: image:
            lib.nameValuePair
            "oci-layout-${lib.replaceStrings [ "-" ] [ "_" ] name}"
            (pkgs.runCommand "oci-layout-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              python3 ${./tests/ci/check-image-tar.py} ${image.oci} ${name}
              touch "$out"
            ''))
          (lib.filterAttrs (name: _: builtins.elem name [ "nix" "nix-dind" ]) images);
      dockerAccessChecks = {
        docker-access-helper = pkgs.runCommand "docker-access-helper" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ]; } ''
          bash ${./tests/ci/check-docker-access.sh} ${compiler.runtimePackages."devcontainer-docker-access"}
          touch "$out"
        '';
      };
      fixtureFiles =
        lib.filterAttrs
          (name: type: type == "regular" && lib.hasSuffix ".nix" name)
          (builtins.readDir ./tests/fixtures);
      fixtureChecks =
        lib.mapAttrs'
          (name: _:
            let
              fixture = import (./tests/fixtures + "/${name}") { inherit self; };
              missing =
                builtins.filter
                  (node: !(builtins.hasAttr node fixture.image.graph.nodes))
                  fixture.expectedNodes;
            in
            lib.nameValuePair
              "fixture-${lib.replaceStrings [ ".nix" "-" ] [ "" "_" ] name}"
              (assert missing == [ ];
                pkgs.writeText
                  "fixture-${name}.json"
                  (builtins.toJSON {
                    image = fixture.image.config.devcontainer.image.name;
                    expectedNodes = fixture.expectedNodes;
                    missing = missing;
                  })))
          fixtureFiles;
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;

      images = images;

      packages.${system} = {
        default = images.nix.reports;
        "devcontainer-image" = compiler.runtimePackages."devcontainer-image";
        "devcontainer-task-runner" = compiler.runtimePackages."devcontainer-task-runner";
        "vscode-extension-projector" = compiler.runtimePackages."vscode-extension-projector";
        "devcontainer-docker-access" = compiler.runtimePackages."devcontainer-docker-access";
        devpkg = compiler.runtimePackages.devpkg;
      };

      checks.${system} = reportChecks // reportCliChecks // ociLayoutChecks // dockerAccessChecks // fixtureChecks;
    };
}
