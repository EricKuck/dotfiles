{
  config,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:
let
  cfg = config.custom.programs.rex;
  owner = config.meta.flake.owner;
  home = config.meta.flake.ownerHome;

  # `rex server run` with no --listen uses the same per-user socket the rex
  # command looks for, so clients find this server instead of autostarting one.
  serverArgs = [
    (lib.getExe cfg.package)
    "server"
    "run"
  ];

  serverEnvironment = {
    # The server only claims TERM=xterm-rex when it can resolve the entry itself.
    # The trailing empty element keeps the compiled-in terminfo defaults.
    TERMINFO_DIRS = "${cfg.package}/share/terminfo:";
    GODEBUG = "";
  };

  # aibox allows exactly this path and denies the server's own socket.
  guardSocket = "${home}/Library/Application Support/rex-guard/guarded.sock";
  serverSocket = "${home}/Library/Application Support/rex/server.sock";
in
{
  options.custom.programs.rex = {
    enable = lib.mkEnableOption "the Rex multiplexer server";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.rex.packages.${system}.rex;
      description = "The Rex package to install and run.";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      environment.systemPackages = [ cfg.package ];
    }
    // (
      if (lib.snowfall.system.is-darwin system) then
        {
          launchd.user.agents.rex.serviceConfig = {
            ProgramArguments = serverArgs;
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
            StandardOutPath = "${home}/Library/Logs/rex.log";
            StandardErrorPath = "${home}/Library/Logs/rex.err.log";
            EnvironmentVariables = serverEnvironment // {
              HOME = home;
            };
          };

          launchd.user.agents.rex-guard.serviceConfig = {
            ProgramArguments = [
              (lib.getExe pkgs.custom.rex-guard)
              "--listen"
              guardSocket
              "--upstream"
              serverSocket
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
            StandardOutPath = "${home}/Library/Logs/rex-guard.log";
            StandardErrorPath = "${home}/Library/Logs/rex-guard.log";
          };
        }
      else
        {
          # A personal server for the owner; lingering (set in the server
          # environment) keeps it running while logged out.
          systemd.user.services.rex = {
            description = "Rex Server";
            documentation = [ "https://superlogical.com" ];
            wantedBy = [ "default.target" ];
            after = [ "network-online.target" ];
            unitConfig.ConditionUser = owner;
            # A restart ends every session; restart by hand after an update.
            restartIfChanged = false;
            environment = serverEnvironment;
            serviceConfig = {
              Type = "notify";
              NotifyAccess = "main";
              ExecStart = lib.escapeShellArgs serverArgs;
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };
        }
    )
  );
}
