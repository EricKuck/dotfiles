{ lib }:
{
  aliasBin =
    {
      pkgs,
      pkg,
      exe,
      alias,
    }:
    pkgs.runCommandLocal "${alias}-alias" { } ''
      mkdir -p $out/bin
      ln -s ${lib.getExe' pkg exe} $out/bin/${alias}
    '';
}
