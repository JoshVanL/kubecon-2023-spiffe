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
    targetSystems = with utils.lib.system; [
      x86_64-linux
      x86_64-darwin
      aarch64-linux
      aarch64-darwin
    ];

    repo = ./.;
    src = nixpkgs.lib.sourceFilesBySuffices ./. [ ".go" "go.mod" "go.sum" "gomod2nix.toml" ];
    version = "aws";

  in utils.lib.eachSystem targetSystems (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            go = prev.go_1_20;
            buildGoApplication = prev.buildGo120Application;
          })
          gomod2nix.overlays.default
        ];
      };

      image = import ./nix/image.nix {
        inherit src pkgs version;
      };

      ci = import ./nix/ci.nix {
        gomod2nix = (gomod2nix.packages.${system}.default);
        images = (image.images localSystem "dev");
        inherit src repo pkgs;
      };

      localSystem = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
      localOS = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux";

    in {
      packages = {
        default = (image.build-driver localSystem localOS);
        driver = (image.build-driver localSystem localOS);
        approver = (image.build-approver localSystem localOS);
        sample-app = (image.build-sample localSystem localOS);
      } // image.packages;

      apps = {
        default = {type = "app"; program = "${self.packages.${system}.default}/bin/dapr-cert-manager"; };
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
