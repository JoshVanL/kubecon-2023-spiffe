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

  build-driver = sys: tag: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/cert-manager-csi-driver";
    contents = with pkgs; [
      mount umount cacert
      (binary-driver sys "linux")
    ];
    config = {
      Entrypoint = [ "cert-manager-csi-driver" ];
    };
  };

  build-approver = sys: tag: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/cert-manager-csi-driver-approver";
    contents = with pkgs; [ (binary-approver sys "linux") ];
    config = {
      User = "1001:1001";
      Entrypoint = [ "cert-manager-csi-driver-approver" ];
    };
  };

  build-sample = sys: tag: pkgs.dockerTools.buildLayeredImage {
    inherit tag;
    name = "${repo}/spiffe-sample-app";
    contents = with pkgs; [
      awscli2
      cacert
      coreutils
      zsh
    ];
    config = { User = "1001:1001"; };
  };

  publish-image = image-name: builder: pkgs.runCommand "publish-image" {
    nativeBuildInputs = with pkgs;[ podman ];
  } ''
    echo ">> Pushing image '${image-name}:${version}'..."
    podman manifest create ${image-name}:${version}
    podman manifest add ${image-name}:${version} docker-archive:${builder "amd64" "${version}-amd64"} --os linux --arch amd64
    podman manifest add ${image-name}:${version} docker-archive:${builder "arm64" "${version}-arm64"} --os linux --arch arm64
    podman push ${image-name}:${version}
  '';

  publish = pkgs.writeShellApplication {
    name = "publish";
    runtimeInputs = with pkgs;[ podman ];
    text = ''
      if [[ -z "''${GITHUB_TOKEN}" ]]; then
        echo ">> Environment varibale 'GITHUB_TOKEN' is not set."
        exit 1
      fi

      echo ">> Logging into GitHub Container Registry..."
      echo "''${GITHUB_TOKEN}" | podman login ghcr.io -u $ --password-stdin

      echo ">> Pushing images..."
      ${publish-image "${repo}/cert-manager-csi-driver" build-driver} &
      ${publish-image "${repo}/cert-manager-csi-driver-approver" build-approver} &
      ${publish-image "${repo}/spiffe-sample-app" build-sample} &
      wait
    '';
  };

in {
  inherit binary-driver binary-approver build-driver build-approver build-sample;

  packages = {
    image-amd64-driver = (build-driver "amd64" "${version}-amd64");
    image-amd64-approver = (build-approver "amd64" "${version}-amd64");
    image-amd64-sample-app = (build-sample "amd64" "${version}-amd64");
    image-arm64-driver = (build-driver "arm64" "${version}-arm64");
    image-arm64-approver = (build-approver "arm64" "${version}-arm64");
    image-arm64-sample-app = (build-sample "arm64" "${version}-arm64");
  };

  images = sys: tag: {
    driver = {
      name = "${repo}/cert-manager-csi-driver";
      tar = (build-driver sys tag);
    };
    approver = {
      name = "${repo}/cert-manager-csi-driver-approver";
      tar = (build-approver sys tag);
    };
    sample-app = {
      name = "${repo}/spiffe-sample-app";
      tar = (build-sample sys tag);
    };
  };

  apps = {
    image-publish = {type = "app"; program = "${publish}/bin/publish";};
  };
}
