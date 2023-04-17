{
pkgs,
src,
version,
}:

let
  repo = "ghcr.io/joshvanl";

  binary-driver = sys: os: (pkgs.buildGoApplication {
    name = "cert-manager-csi-driver";
    modules = ../gomod2nix.toml;
    inherit src;
    subPackages = [ "cmd/csi" ];
  }).overrideAttrs(old: old // {
    GOOS = os;
    GOARCH = sys;
    CGO_ENABLED = "0";
    postInstall = ''
      mv $(find $out -type f) $out/bin/cert-manager-csi-driver
      find $out -empty -type d -delete
    '';
  });

  binary-approver = sys: os: (pkgs.buildGoApplication {
    name = "cert-manager-csi-driver-approver";
    modules = ../gomod2nix.toml;
    inherit src;
    subPackages = [ "cmd/approver" ];
  }).overrideAttrs(old: old // {
    GOOS = os;
    GOARCH = sys;
    CGO_ENABLED = "0";
    postInstall = ''
      mv $(find $out -type f) $out/bin/cert-manager-csi-driver-approver
      find $out -empty -type d -delete
    '';
  });

  build-driver = sys: tag: crossPkgs: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/cert-manager-csi-driver";
    contents = with crossPkgs; [
      mount umount cacert
      (binary-driver sys "linux")
    ];
    config = {
      Entrypoint = [ "cert-manager-csi-driver" ];
    };
  };

  build-driver-amd = version:
    (build-driver "amd64" "${version}-amd64" pkgs.pkgsCross.gnu64);

  build-driver-arm = version:
    (build-driver "arm64" "${version}-arm64" pkgs.pkgsCross.aarch64-multiplatform);

  build-approver = sys: tag: crossPkgs: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/cert-manager-csi-driver-approver";
    contents = [ (binary-approver sys "linux") ];
    config = {
      User = "1001:1001";
      Entrypoint = [ "cert-manager-csi-driver-approver" ];
    };
  };

  build-approver-amd = version:
    (build-approver "amd64" "${version}-amd64" pkgs.pkgsCross.gnu64);

  build-approver-arm = version:
    (build-approver "arm64" "${version}-arm64" pkgs.pkgsCross.aarch64-multiplatform);

  build-sample = sys: tag: crossPkgs: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/spiffe-sample-app";
    contents = with crossPkgs; [
      awscli2
      cacert
      coreutils
      zsh
    ];
    config = { User = "1001:1001"; };
  };

  build-sample-amd = version:
    (build-sample "amd64" "${version}-amd64" pkgs.pkgsCross.gnu64);

  build-sample-arm = version:
    (build-sample "arm64" "${version}-arm64" pkgs.pkgsCross.aarch64-multiplatform);

  publish = pkgs.writeShellApplication {
    name = "publish";
    runtimeInputs = with pkgs;[ podman gcc ];
    text = ''
      echo ">> Pushing images..."

      if [[ -z "''${GITHUB_TOKEN}" ]]; then
        echo ">> Environment varibale 'GITHUB_TOKEN' is not set."
        exit 1
      fi

      echo ">> Logging into GitHub Container Registry..."
      echo "''${GITHUB_TOKEN}" | podman login ghcr.io -u $ --password-stdin

      DRIVER_IMAGE="${repo}/cert-manager-csi-driver:${version}"
      APPROVER_IMAGE="${repo}/cert-manager-csi-driver-approver:${version}"
      SAMPLE_APP_IMAGE="${repo}/spiffe-sample-app:${version}"

      podman manifest create $DRIVER_IMAGE
      podman manifest add $DRIVER_IMAGE docker-archive:${build-driver-amd version} --os linux --arch amd64
      podman manifest add $DRIVER_IMAGE docker-archive:${build-driver-arm version} --os linux --arch arm64
      podman push $DRIVER_IMAGE

      podman manifest create $APPROVER_IMAGE
      podman manifest add $APPROVER_IMAGE docker-archive:${build-approver-amd version} --os linux --arch amd64
      podman manifest add $APPROVER_IMAGE docker-archive:${build-approver-arm version} --os linux --arch arm64
      podman push $APPROVER_IMAGE

      podman manifest create $SAMPLE_APP_IMAGE
      podman manifest add $SAMPLE_APP_IMAGE docker-archive:${build-sample-amd version} --os linux --arch amd64
      podman manifest add $SAMPLE_APP_IMAGE docker-archive:${build-sample-arm version} --os linux --arch arm64
      podman push $SAMPLE_APP_IMAGE
    '';
  };

in {
  inherit build-driver build-approver build-sample;

  packages = {
    image-amd64-driver = build-driver-amd version;
    image-amd64-approver = build-approver-amd version;
    image-amd64-sample-app = build-sample-amd version;
    image-arm64-driver = build-driver-arm version;
    image-arm64-approver = build-approver-arm version;
    image-arm64-sample-app = build-sample-arm version;
  };

  images = sys: tag: {
    driver = {
      name = "${repo}/cert-manager-csi-driver";
      tar = (build-driver sys tag pkgs);
    };
    approver = {
      name = "${repo}/cert-manager-csi-driver-approver";
      tar = (build-approver sys tag pkgs);
    };
    sample-app = {
      name = "${repo}/spiffe-sample-app";
      tar = (build-sample sys tag pkgs);
    };
  };

  apps = {
    image-publish = {type = "app"; program = "${publish}/bin/publish";};
  };
}
