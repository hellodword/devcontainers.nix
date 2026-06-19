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
            image.reports)
          images;
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;

      images = images;

      packages.${system} = {
        default = images.nix.reports;
      };

      checks.${system} = reportChecks;
    };
}
