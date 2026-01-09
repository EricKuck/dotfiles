{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  cfg = config.services.custom.mxroute-manager;
in
{
  options.services.custom.mxroute-manager = {
    enable = mkEnableOption "MXRoute Manager web application";

    package = mkOption {
      type = types.package;
      default = pkgs.custom.mxroute-manager;
      description = "The mxroute-manager package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "mxroute-manager";
      description = "User account under which mxroute-manager runs.";
    };

    group = mkOption {
      type = types.str;
      default = "mxroute-manager";
      description = "Group under which mxroute-manager runs.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to.";
    };

    port = mkOption {
      type = types.port;
      default = 2121;
      description = "Port to listen on.";
    };

    workers = mkOption {
      type = types.int;
      default = 4;
      description = "Number of gunicorn worker processes.";
    };

    mxrouteServer = mkOption {
      type = types.path;
      description = "MXRoute API server hostname.";
    };

    mxrouteUsername = mkOption {
      type = types.path;
      description = "MXRoute API username sops secret.";
    };

    mxrouteApiKeyFile = mkOption {
      type = types.path;
      description = "MXRoute API key sops secret.";
    };

    allowedEmailsFile = mkOption {
      type = types.path;
      description = "Allowed destination emails sops secret.";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables to set.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for the specified port.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mxrouteApiKeyFile != null;
        message = "services.custom.mxroute-manager.mxrouteApiKeyFile must be set";
      }
      {
        assertion = cfg.allowedEmailsFile != null;
        message = "services.custom.mxroute-manager.allowedEmailsFile must be set";
      }
      {
        assertion = cfg.mxrouteUsername != null;
        message = "services.custom.mxroute-manager.mxrouteUsername must be set";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "MXRoute Manager service user";
    };

    users.groups.${cfg.group} = { };

    systemd.services.mxroute-manager = {
      description = "MXRoute Manager web application";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        MXROUTE_SERVER = cfg.mxrouteServer;
      }
      // cfg.extraEnvironment;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        RestartSec = "10s";

        # Security settings
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;

        # Working directory
        WorkingDirectory = "${cfg.package}/lib/mxroute-manager";

        # Load secrets from sops files
        LoadCredential = [
          "mxroute-server:${cfg.mxrouteServer}"
          "mxroute-username:${cfg.mxrouteUsername}"
          "mxroute-api-key:${cfg.mxrouteApiKeyFile}"
          "allowed-emails:${cfg.allowedEmailsFile}"
        ];

        # Start script that loads secrets and runs the application
        ExecStart = pkgs.writeShellScript "mxroute-manager-start" ''
          export MXROUTE_SERVER="$(cat $CREDENTIALS_DIRECTORY/mxroute-server)"
          export MXROUTE_USERNAME="$(cat $CREDENTIALS_DIRECTORY/mxroute-username)"
          export MXROUTE_API_KEY="$(cat $CREDENTIALS_DIRECTORY/mxroute-api-key)"
          export ALLOWED_EMAILS="$(cat $CREDENTIALS_DIRECTORY/allowed-emails)"
          exec ${cfg.package}/bin/mxroute-manager-gunicorn \
            --workers ${toString cfg.workers} \
            --bind ${cfg.host}:${toString cfg.port}
        '';
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
