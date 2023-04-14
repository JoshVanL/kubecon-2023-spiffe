{
pkgs,
gomod2nix,
images,
src,
repo,
}:

let
  checkgomod2nix = pkgs.writeShellApplication {
    name = "check-gomod2nix";
    runtimeInputs = [ gomod2nix ];
    text = ''
      tmpdir=$(mktemp -d)
      trap 'rm -rf -- "$tmpdir"' EXIT
      gomod2nix --dir "$1" --outdir "$tmpdir"
      if ! diff -q "$tmpdir/gomod2nix.toml" "$1/gomod2nix.toml"; then
        echo '>> gomod2nix.toml is not up to date. Please run:'
        echo '>> $ nix run .#update'
        exit 1
      fi
      echo '>> gomod2nix.toml is up to date'
    '';
  };

  demo-loadimage-docker = pkgs.writeShellApplication {
    name = "demo-loadimage-docker";
    runtimeInputs = with pkgs; [
      docker
      kind
    ];
    text = ''
      (docker load < ${images.driver.tar} && kind load --name spiffe-aws docker-image ${images.driver.name}:dev) &
      (docker load < ${images.approver.tar} && kind load --name spiffe-aws docker-image ${images.approver.name}:dev) &
      (docker load < ${images.sample-app.tar} && kind load --name spiffe-aws docker-image ${images.sample-app.name}:dev) &
      wait
    '';
  };

  demo-loadimage-podman = pkgs.writeShellApplication {
    name = "demo-loadimage-podman";
    runtimeInputs = with pkgs; [
      podman
      kind
    ];
    text = ''
      export KIND_EXPERIMENTAL_PROVIDER=podman
      (podman load < ${images.driver.tar} && kind load --name spiffe-aws docker-image ${images.driver.name}:dev) &
      (podman load < ${images.approver.tar} && kind load --name spiffe-aws docker-image ${images.approver.name}:dev) &
      (podman load < ${images.sample-app.tar} && kind load --name spiffe-aws docker-image ${images.sample-app.name}:dev) &
      wait
    '';
  };

  demo-loadimage = pkgs.writeShellApplication {
    name = "demo-loadimage";
    runtimeInputs = with pkgs; [
      demo-loadimage-docker
      demo-loadimage-podman
    ];
    text = ''
      if docker version > /dev/null && [[ -S /var/run/docker.sock ]]; then
        demo-loadimage-docker
      else
        demo-loadimage-podman
      fi
    '';
  };

  demo = pkgs.writeShellApplication {
    name = "demo";
    runtimeInputs = with pkgs; [
      demo-loadimage
      kubernetes-helm
      kubectl
      kind
    ];
    text = ''
      TMPDIR="''${TMPDIR:-$(mktemp -d)}"
      echo ">> using tmpdir: $TMPDIR"

      kind create cluster --kubeconfig "$TMPDIR/kubeconfig" --name spiffe-aws

      demo-loadimage

      export KUBECONFIG="$TMPDIR/kubeconfig"
      echo ">> using kubeconfig: $KUBECONFIG"
      echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
      echo "export KUBECONFIG=$KUBECONFIG"
      echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
      echo ">> installing cert-manager, and CSI driver SPIFFE"

      helm repo add --force-update jetstack https://charts.jetstack.io
      helm upgrade --install cert-manager jetstack/cert-manager --create-namespace --namespace cert-manager --set installCRDs=true --wait

      kubectl apply -f ${repo}/deploy/example/clusterissuer.yaml

      helm upgrade -i -n cert-manager cert-manager-csi-driver-spiffe ./deploy/charts/csi-driver-spiffe --wait \
        --set app.logLevel=2 \
        --set image.repository.driver=${images.driver.name} \
        --set image.repository.approver=${images.approver.name} \
        --set image.tag=dev \
        --set app.trustDomain=cert-manager.kubecon2023 \
        --set app.approver.signerName=clusterissuers.cert-manager.io/csi-driver-spiffe-ca \
        --set app.issuer.name=csi-driver-spiffe-ca \
        --set app.driver.volumes[0].name=root-cas \
        --set app.driver.volumes[0].secret.secretName=csi-driver-spiffe-ca \
        --set app.driver.volumeMounts[0].name=root-cas \
        --set app.driver.volumeMounts[0].mountPath=/var/run/secrets/cert-manager-csi-driver-spiffe \
        --set app.driver.sourceCABundle=/var/run/secrets/cert-manager-csi-driver-spiffe/ca.crt

      kubectl apply -f ${repo}/nix/example-app.yaml
    '';
  };

  update = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = [
      gomod2nix
    ];
    text = ''
      gomod2nix
      gomod2nix --dir test/e2e
      echo '>> Updated. Please commit the changes.'
    '';
  };

  check = pkgs.writeShellApplication {
    name = "check";
    runtimeInputs = [
      checkgomod2nix
    ];
    text = ''
      check-gomod2nix ${repo}
      check-gomod2nix ${repo}/test/e2e
    '';
  };

in {
  apps = {
    update = {type = "app"; program = "${update}/bin/update";};
    check = {type = "app"; program = "${check}/bin/check";};
    demo-loadimage = {type = "app"; program = "${demo-loadimage}/bin/demo-loadimage";};
    demo = {type = "app"; program = "${demo}/bin/demo";};
  };
}
