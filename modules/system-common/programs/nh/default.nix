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

    flake = lib.mkOption {
      type = lib.types.str;
      description = ''
        The path that will be used for the `NH_FLAKE` environment variable.

        `NH_FLAKE` is used by nh as the default flake for performing actions, like `nh os switch`.
      '';
    };

    clean = {
      enable = lib.mkEnableOption "periodic garbage collection with nh clean all";

      extraArgs = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "";
        example = "--keep 5 --keep-since 3d";
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

        {
          assertion = (cfg.flake != null) -> !(lib.hasSuffix ".nix" cfg.flake);
          message = "nh.flake must be a directory, not a nix file";
        }
      ];

      environment = lib.mkIf cfg.enable {
        systemPackages = with pkgs; [ nh ];
        variables = {
          NH_FLAKE = cfg.flake;
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
