{
  config,
  lib,
  pkgs,
  system,
  ...
}:
let
  cfg = config.custom.programs.nh;
in
{
  options.custom.programs.nh = {
    enable = lib.mkEnableOption "nh";

    clean = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "periodic garbage collection with nh clean all";
      };

      extraArgs = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "--keep-since 4d --keep 3";
        description = ''
          Options given to nh clean when the service is run automatically.

          See `nh clean all --help` for more information.
        '';
      };
    };
  };

  config =
    {
      warnings =
        if (!(cfg.clean.enable -> !config.nix.gc.automatic)) then
          [
            "programs.nh.clean.enable and nix.gc.automatic are both enabled. Please use one or the other to avoid conflict."
          ]
        else
          [ ];

      assertions = [
        # Not strictly required but probably a good assertion to have
        {
          assertion = cfg.clean.enable -> cfg.enable;
          message = "programs.nh.clean.enable requires programs.nh.enable";
        }
      ];

      environment = lib.mkIf cfg.enable {
        systemPackages = with pkgs; [ nh ];
        variables = {
          NH_FLAKE = "path:${config.meta.flake.path}";
        };
      };
    }
    // (
      if (lib.snowfall.system.is-darwin system) then
        {
          launchd = lib.mkIf cfg.clean.enable {
            agents = {
              nh-clean = {
                command = "exec ${lib.getExe pkgs.nh} clean all ${cfg.clean.extraArgs}";
                serviceConfig = {
                  StartInterval = 604800; # Weekly
                };
              };
            };
          };
        }
      else
        {
          systemd = lib.mkIf cfg.clean.enable {
            services.nh-clean = {
              description = "nh clean";
              script = "exec ${lib.getExe pkgs.nh} clean all ${cfg.clean.extraArgs}";
              startAt = "weekly";
              path = [ config.nix.package ];
              serviceConfig.Type = "oneshot";
            };

            timers.nh-clean = {
              timerConfig = {
                Persistent = true;
              };
            };
          };
        }
    );
}
