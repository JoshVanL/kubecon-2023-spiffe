{ pkgs, ... }:
with pkgs;
{
  helm-docs = callPackage ./helm-docs {};
}
