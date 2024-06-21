{ ... }:

_final: prev:

let
  xero-figlet-fonts = prev.pkgs.fetchFromGitHub {
    owner = "xero";
    repo = "figlet-fonts";
    rev = "0c0697139d6db66878eee720ebf299bc3a605fd0";
    sha256 = "sha256-HmO968OYH5yWwsDRp7HVfWvp48upUv+YwZxcMxBHNSw=";
  };
in
{
  figlet = prev.figlet.overrideAttrs (old: rec {
    postInstall = prev.lib.intersperse "\n" [
      old.postInstall
      "cp -nr ${xero-figlet-fonts}/*.flf $out/share/figlet/"
    ];
  });
}
