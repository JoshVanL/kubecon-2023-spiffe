{
  description = "cert-manager-csi-spiffe";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    gomod2nix = {
      url = "github:tweag/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };
  };

  outputs = { self, nixpkgs, utils, gomod2nix }:
  let
    lib = nixpkgs.lib;
    targetSystems = with utils.lib.system; [
      x86_64-linux
      x86_64-darwin
      aarch64-linux
      aarch64-darwin
    ];

    repo = nixpkgs.lib.sourceFilesBySuffices ./. [ ".go" "go.mod" "go.sum" "gomod2nix.toml" ".yaml" ];
    src = nixpkgs.lib.sourceFilesBySuffices ./. [ ".go" "go.mod" "go.sum" "gomod2nix.toml" ];
    version = "aws";

  in utils.lib.eachSystem targetSystems (system:
    let
      overlays = lib.mapAttrsToList (name: _: import ./nix/overlays/${name})
      (lib.filterAttrs
        (name: entryType: lib.hasSuffix ".nix" name) (builtins.readDir ./nix/overlays)
      ) ++ [ gomod2nix.overlays.default ];

      pkgs = import nixpkgs {
        inherit system overlays;
        config.packageOverrides = (import ./nix/pkgs/default.nix);
      };
      amdPkgs = import nixpkgs { inherit overlays; system = "x86_64-linux"; };
      armPkgs = import nixpkgs { inherit overlays; system = "aarch64-linux"; };

      image = import ./nix/image.nix { inherit src pkgs amdPkgs armPkgs version; };

      ci = import ./nix/ci.nix {
        gomod2nix = (gomod2nix.packages.${system}.default);
        inherit repo pkgs;
      };

      demo = import ./nix/demo.nix {
        images = (image.images localSystem "dev");
        inherit repo pkgs;
      };

      localSystem = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";

    in {
      packages = {
        default = (image.build-driver localSystem "dev" pkgs);
        driver = (image.build-driver localSystem "dev" pkgs);
        approver = (image.build-approver localSystem "dev" pkgs);
        sample-app = (image.build-sample localSystem "dev" pkgs);
      } // image.packages;

      apps = {
        default = {type = "app"; program = "${self.packages.${system}.default}/bin/cert-manager-csi-driver"; };
      } // image.apps // ci.apps;

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          go
          gopls
          gotools
          go-tools
          gomod2nix.packages.${system}.default
        ];
      };
  });
}
