{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    filterAttrs
    mapAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.custom.prometheus-exporters;
  enabledExporters = filterAttrs (_: v: v.enable) cfg;
  exportersWithRules = lib.filterAttrs (_: v: v.rules != [ ]) enabledExporters;
  exportersWithManagedUsers = lib.filterAttrs (_: v: v.systemd.createUser) enabledExporters;
  exportersWithSystemServices = lib.filterAttrs (_: v: !v.systemd.isUserService) enabledExporters;
  exportersWithUserServices = lib.filterAttrs (_: v: v.systemd.isUserService) enabledExporters;

  ruleFiles = lib.mapAttrsToList (
    name: exporter:
    pkgs.writeTextFile {
      name = "${name}-rules.yaml";
      text = lib.generators.toYAML { } { groups = exporter.rules; };
    }
  ) exportersWithRules;

  mkSystemdUnit = name: exporter: {
    Description = "Prometheus ${name} exporter";
    After = [
      "network.target"
      "sops-nix.service"
    ];
  };

  mkSystemdService = name: exporter: {
    ExecStart = exporter.systemd.execStart;
    Restart = "always";
    Environment =
      let
        baseEnv = exporter.systemd.environment;
        pathEnv = lib.optionalAttrs (exporter.systemd.path != [ ]) {
          PATH = lib.makeBinPath exporter.systemd.path;
        };
      in
      lib.mapAttrsToList (k: v: "${k}=${v}") (baseEnv // pathEnv);
    EnvironmentFile = lib.mkIf (
      exporter.systemd.environmentFile != null
    ) exporter.systemd.environmentFile;
    ExecReload = lib.mkIf (exporter.systemd.execReload != null) exporter.systemd.execReload;
    User = lib.mkIf (!exporter.systemd.isUserService) exporter.systemd.user;
    Group = lib.mkIf (!exporter.systemd.isUserService) exporter.systemd.group;
    AmbientCapabilities = exporter.systemd.ambientCapabilities;
  };
in
{
  options.services.custom.prometheus-exporters = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkEnableOption "Prometheus exporter ${name}";

            port = lib.mkOption {
              type = lib.types.port;
              description = "Port the ${name} exporter listens on.";
            };

            scrape = mkOption {
              type = types.submodule {
                options = {
                  interval = lib.mkOption {
                    type = types.nullOr lib.types.str;
                    default = "10s";
                    description = "Scrape interval for the ${name} Prometheus job. Setting to null disables the default scraper.";
                  };

                  metricsPath = lib.mkOption {
                    type = lib.types.str;
                    default = "/metrics";
                    description = "Path from which the default scrape job should collect metrics.";
                  };

                  configs = lib.mkOption {
                    type = lib.types.listOf types.attrs;
                    default = [ ];
                    description = "Scrape configs for the ${name} exporter.";
                  };
                };
              };
              default = { };
              description = "Scrape configuration for the ${name} exporter.";
            };

            rules = lib.mkOption {
              type = lib.types.listOf types.attrs;
              default = [ ];
              description = "Alerting/recording rules for the ${name} exporter.";
            };

            systemd = mkOption {
              type = types.submodule {
                options = {
                  isUserService = mkEnableOption "Whether or not the systemd service will be a user service (vs a system service) for the ${name} exporter";

                  execStart = mkOption {
                    type = types.str;
                    description = "The ExecStart command for the ${name} systemd service.";
                  };

                  execReload = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Optional command to execute on systemd reload.";
                  };

                  path = mkOption {
                    type = types.listOf types.package;
                    default = [ ];
                    description = "The path env var for the ${name} exporter.";
                  };

                  environment = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Inline environment variables.";
                  };

                  environmentFile = mkOption {
                    type = types.nullOr types.path;
                    default = null;
                    description = "Optional path to an environment file.";
                  };

                  createUser = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Whether or not a user and group should be created for the ${name} exporter.";
                  };

                  user = mkOption {
                    type = types.str;
                    default = "${name}-exporter";
                    description = "The user under which the exporter will run.";
                  };

                  group = mkOption {
                    type = types.str;
                    default = "${name}-exporter";
                    description = "The group under which the exporter will run.";
                  };

                  extraUserGroups = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Additional groups for the ${name} exporter user.";
                  };

                  ambientCapabilities = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Ambient capabilities for the ${name} exporter.";
                  };
                };
              };
              default = { };
              description = "Systemd configuration for the ${name} exporter.";
            };
          };
        }
      )
    );
    default = { };
  };

  config = {
    users = {
      users = mapAttrs' (_: exporter: {
        name = exporter.systemd.user;
        value = {
          isSystemUser = true;
          group = exporter.systemd.group;
          extraGroups = exporter.systemd.extraUserGroups;
        };
      }) exportersWithManagedUsers;

      groups = mapAttrs' (_: exporter: {
        name = exporter.systemd.group;
        value = { };
      }) exportersWithManagedUsers;
    };

    systemd.services = lib.mapAttrs' (name: exporter: {
      name = "prometheus-${name}-exporter";
      value = {
        unitConfig = mkSystemdUnit name exporter;
        serviceConfig = mkSystemdService name exporter;
        wantedBy = [ "multi-user.target" ];
      };
    }) exportersWithSystemServices;

    home-manager.users.eric.systemd.user.services = lib.mapAttrs' (name: exporter: {
      name = "prometheus-${name}-exporter";
      value = {
        Unit = mkSystemdUnit name exporter;
        Service = mkSystemdService name exporter;
        Install.WantedBy = [ "default.target" ];
      };
    }) exportersWithUserServices;

    services.prometheus = {
      scrapeConfigs = lib.mkBefore (
        lib.flatten (
          lib.mapAttrsToList (
            name: exporter:
            lib.optional (exporter.scrape.interval != null) {
              job_name = name;
              scrape_interval = exporter.scrape.interval;
              metrics_path = exporter.scrape.metricsPath;
              static_configs = [
                {
                  targets = [ "localhost:${toString exporter.port}" ];
                }
              ];
            }
          ) enabledExporters
          ++ lib.mapAttrsToList (_: exporter: exporter.scrape.configs) enabledExporters
        )
      );

      ruleFiles = ruleFiles;
    };
  };
}
