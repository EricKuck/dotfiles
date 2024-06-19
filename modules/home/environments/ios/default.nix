{
  lib,
  config,
  pkgs,
  format,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.ios;
in
{
  options.custom.environments.ios = {
    enable = mkEnableOption "ios";
  };

  config.home.packages =
    if format == "darwin" then
      [ pkgs.cocoapods ]
    else
      throw "iOS environment only available for darwin targets";
}
