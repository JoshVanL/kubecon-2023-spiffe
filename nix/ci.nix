{
pkgs,
gomod2nix,
repo,
demo,
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

  checkhelmdocs = pkgs.writeShellApplication {
    name = "check-helmdocs";
    runtimeInputs = with pkgs; [ helm-docs ];
    text = ''
      tmpdir=$(mktemp -d)
      trap 'rm -rf -- "$tmpdir"' EXIT
      helm-docs ${repo}/deploy/charts/csi-driver-spiffe -d -l error > "$tmpdir/README.md"
      if ! diff -q "$tmpdir/README.md" "${repo}/deploy/charts/csi-driver-spiffe/README.md"; then
        echo '>> helm docs is are up to date. Please run:'
        echo '>> $ nix run .#update'
        exit 1
      fi
      echo '>> helm docs is up to date'
    '';
  };

  checkboilerplate = pkgs.writeShellApplication {
    name = "check-boilerplate";
    runtimeInputs = with pkgs; [ python3 ];
    text = ''
      mapfile -t files_need_boilerplate < <(${repo}/nix/assets/boilerplate/boilerplate.py "$@")
      if [[ "''${#files_need_boilerplate[@]}" -gt 0 ]]; then
        for file in "''${files_need_boilerplate[@]}"; do
          echo "Boilerplate header is wrong for: $file"
        done
        exit 1
      fi
    '';
  };

  update = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = with pkgs; [
      gomod2nix
      helm-docs
    ];
    text = ''
      gomod2nix
      gomod2nix --dir test/e2e
      helm-docs ./deploy/charts/csi-driver-spiffe
      echo '>> Updated. Please commit the changes.'
    '';
  };

  check = pkgs.writeShellApplication {
    name = "check";
    runtimeInputs = [
      checkgomod2nix
      checkhelmdocs
      checkboilerplate
    ];
    text = ''
      check-gomod2nix ${repo}
      check-gomod2nix ${repo}/test/e2e
      check-helmdocs
      check-boilerplate
    '';
  };

  e2e = pkgs.writeShellApplication {
    name = "e2e";
    runtimeInputs = with pkgs; [
      demo
      kind
      ginkgo
    ];
    text = ''
      demo

      TMPDIR="''${TMPDIR:-$(mktemp -d)}"
      kind get kubeconfig --name spiffe-aws > "$TMPDIR/kubeconfig.yaml"

      ginkgo -nodes 1 ${repo}/test/e2e/. -- --kubeconfig-path "$TMPDIR/kubeconfig.yaml" --kubectl-path ${pkgs.kubectl}/bin/kubectl
    '';
  };

in {
  apps = {
    update = {type = "app"; program = "${update}/bin/update";};
    check = {type = "app"; program = "${check}/bin/check";};
    e2e = {type = "app"; program = "${e2e}/bin/e2e";};
  };
}
