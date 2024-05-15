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
  cfg = config.custom.environments.ios;
in
{
  options.custom.environments.ios = {
    enable = mkEnableOption "ios";
  };

  config = mkIf cfg.enable {
    homebrew = {
      masApps = {
        Xcode = 497799835;
      };
    };
  };
}
