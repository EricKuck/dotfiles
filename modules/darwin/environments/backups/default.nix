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
  cfg = config.custom.environments.backups;
in
{
  options.custom.environments.backups = {
    enable = mkEnableOption "backups";
  };

  config = mkIf cfg.enable {
    environment = {
      shellAliases = {
        kopia = "/Applications/KopiaUI.app/Contents/Resources/server/kopia";
      };
    };

    homebrew = {
      casks = [ "kopiaui" ];
    };
  };
}
