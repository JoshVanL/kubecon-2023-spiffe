final: prev: {
  cmctl = let
    version = "1.11.1";
    src = prev.fetchFromGitHub {
      owner = "cert-manager";
      repo = "cert-manager";
      rev = "v${version}";
      sha256 = "sha256-oCExwBrhVXfZxrOE4PTI4LfwCYFx0TR2ro9eIApsBBE=";
    };
  in
  prev.cmctl.override rec {
    buildGoModule = args: prev.buildGoModule ( args // {
      inherit src version;
      vendorSha256 = "sha256-tKvvqYGwLEoSfGzBRLx8xC/0Kz1uLmHYQ+gcHOW+550=";
        ldflags = [
          "-s" "-w"
          "-X github.com/cert-manager/cert-manager/cmd/ctl/pkg/build.name=cmctl"
          "-X github.com/cert-manager/cert-manager/cmd/ctl/pkg/build/commands.registerCompletion=true"
          "-X github.com/cert-manager/cert-manager/pkg/util.AppVersion=v${version}"
          "-X github.com/cert-manager/cert-manager/pkg/util.AppGitCommit=${src.rev}"
        ];
    });
  };
}
