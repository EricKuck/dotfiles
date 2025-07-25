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

  kopiaignore = builtins.path {
    path = ./kopiaignore;
    name = "kopiaignore";
  };

  backups = [
    config.meta.flake.ownerHome
    "${config.meta.flake.ownerHome}/Code" # Needed as separate entry since it's a volume
  ];
in
{
  options.custom.environments.backups = {
    enable = mkEnableOption "backups";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ kopia ];

    system.activationScripts.postActivation.text = ''
      for dir in ${lib.strings.concatStringsSep " " backups}; do
        KOPIAIGNORE="$dir/.kopiaignore"
        ln -sfn ${kopiaignore} $KOPIAIGNORE
      done
    '';

    launchd = {
      user = {
        agents = {
          kopia-backup = {
            command = "${lib.getExe' pkgs.kopia "kopia"} snapshot create ${lib.strings.concatStringsSep " " backups}";
            serviceConfig = {
              StartInterval = 3600;
            };
          };

          kopia-server = {
            command = "${lib.getExe' pkgs.kopia "kopia"} server start --insecure --without-password";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
            };
          };
        };
      };
    };
  };
}
