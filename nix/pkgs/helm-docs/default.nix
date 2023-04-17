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
    hash = "sha256-YAa5Dr8Pc6P3RZ3SCiyi7zwmVd5tPalM88R8bxgg6Ja=";
  };

  vendorSha256 = "sha256-J/sJd2LLMBr53Z3sGrWgnWA8Ry+XqqfCEObqFyUD96a=";

  nativeBuildInputs = [ installShellFiles ];
  postInstall = ''
    installShellCompletion --cmd helm-docs \
      --bash <($out/bin/helm-docs completion bash) \
      --fish <($out/bin/helm-docs completion fish) \
      --zsh <($out/bin/helm-docs completion zsh)
  '';

  meta = with lib; {
    homepage = "https://github.com/norwoodj/helm-docs";
    description = "TODO";
    longDescription = ''
      The helm-docs tool auto-generates documentation from helm charts into
      markdown files. The resulting files contain metadata about their
      respective chart and a table with each of the chart's values, their
      defaults, and an optional description parsed from comments.
    '';
    license = licenses.gpl;
  };
}
