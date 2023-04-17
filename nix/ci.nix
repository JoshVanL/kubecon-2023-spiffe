{
pkgs,
gomod2nix,
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
  };
}
