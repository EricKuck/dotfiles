{
  lib,
  pkgs,
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
      taps = [
        "pbreault/gww"
        "borneygit/brew"
      ];

      brews = [
        "gradle-profiler"
        "pbreault/gww/gww"
        "borneygit/brew/pidcat"
      ];

      casks = [
        {
          name = "android-studio";
          greedy = true;
        }
        {
          name = "android-studio-preview@canary";
          greedy = true;
        }
      ];
    };

    environment = {
      systemPackages = with pkgs; [
        kotlin
      ];

      shellAliases = {
        gw = "gww";
      };
    };
  };
}
