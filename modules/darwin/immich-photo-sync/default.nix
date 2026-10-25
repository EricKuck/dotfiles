{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.custom.services.immich-photo-sync;
  home = config.meta.flake.ownerHome;
in
{
  options.custom.services.immich-photo-sync = {
    enable = mkEnableOption "syncing the owner's Photos library to Immich";

    package = mkOption {
      type = types.package;
      default = pkgs.immich-photo-sync;
      defaultText = "pkgs.immich-photo-sync";
    };

    server = mkOption {
      type = types.str;
      example = "https://photos.example.com";
      description = "Immich server URL.";
    };

    apiKeyFile = mkOption {
      type = types.str;
      description = "File containing the Immich API key, readable by the owner.";
    };

    interval = mkOption {
      type = types.str;
      default = "1h";
      description = "Full reconciliation cadence in humantime syntax; 0 leaves only the live change watcher.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "--include-hidden"
        "--replace-stale-edits"
      ];
      description = "Additional immich-photo-sync flags.";
    };
  };

  config = mkIf cfg.enable {
    # A user agent, not a daemon: PhotoKit needs the owner's GUI session and Photos permission.
    launchd.user.agents.immich-photo-sync.serviceConfig = {
      ProgramArguments = [
        (lib.getExe cfg.package)
        "--server"
        cfg.server
        "--api-key-file"
        cfg.apiKeyFile
        "--state-dir"
        "${home}/Library/Application Support/immich-photo-sync"
        "--interval"
        cfg.interval
      ]
      ++ cfg.extraArgs
      ++ [ "run" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 60;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${home}/Library/Logs/immich-photo-sync.log";
      StandardErrorPath = "${home}/Library/Logs/immich-photo-sync.err.log";
      EnvironmentVariables.HOME = home;
    };
  };
}
