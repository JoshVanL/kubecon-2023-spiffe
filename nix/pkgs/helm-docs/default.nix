{ lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
}:

buildGoModule rec {
  pname = "helm-docs";
  version = "1.9.1";

  src = fetchFromGitHub {
    owner = "norwoodj";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-1ifaiKEKvHdrcJEfcN0bFtzNTesmPn1rwzP2Eul7Yck=";
  };

  vendorSha256 = "sha256-FpmeOQ8nV+sEVu2+nY9o9aFbCpwSShQUFOmyzwEQ9Pw=";

  nativeBuildInputs = [ installShellFiles ];
  postInstall = ''
    installShellCompletion --cmd helm-docs \
      --bash <($out/bin/helm-docs completion bash) \
      --fish <($out/bin/helm-docs completion fish) \
      --zsh <($out/bin/helm-docs completion zsh)
  '';

  meta = with lib; {
    homepage = "https://github.com/norwoodj/helm-docs";
    description = "A tool for automatically generating markdown documentation for helm charts";
    longDescription = ''
      The helm-docs tool auto-generates documentation from helm charts into
      markdown files. The resulting files contain metadata about their
      respective chart and a table with each of the chart's values, their
      defaults, and an optional description parsed from comments.
    '';
    license = licenses.gpl3;
  };
}
