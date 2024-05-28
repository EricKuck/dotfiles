{
  lib,
  pkgs,
  inputs,
  system,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.android;
in
{
  options.custom.environments.android = {
    enable = mkEnableOption "android";
  };

  config = mkIf cfg.enable {
    homebrew = {
      taps = [ "pbreault/gww" ];

      brews = [
        "gradle-profiler"
        "pbreault/gww/gww"
      ];

      casks = [ "android-studio" ];
    };

    environment = {
      shellAliases = {
        gw = "gww";
      };
    };
  };
}
