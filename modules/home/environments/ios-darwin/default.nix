{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.ios-darwin;
in
{
  options.custom.environments.ios-darwin = {
    enable = mkEnableOption "ios-darwin";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [ cocoapods ];
    };
  };
}
