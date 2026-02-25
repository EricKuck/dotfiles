{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.caddy-with-blackbox;
in
{
  options = {
    custom.blackboxConfig = mkOption {
      type = types.submodule {
        options = {
          disabled = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of hostnames to disable blackbox monitoring for.";
          };

          paths = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Custom health check paths for hostnames.";
          };

          allow40x = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of hostnames that allow 4xx HTTP responses.";
          };
        };
      };
      default = { };
      description = "Blackbox monitoring configuration extracted from Caddy virtual hosts.";
    };

    services.caddy-with-blackbox = {
      virtualHosts = mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                extraConfig = mkOption {
                  type = types.lines;
                  default = "";
                  description = "Additional configuration for this virtual host.";
                };

                blackbox = mkOption {
                  type = types.submodule {
                    options = {
                      disabled = mkOption {
                        type = types.bool;
                        default = false;
                        description = "Whether to disable blackbox monitoring for this virtual host.";
                      };

                      path = mkOption {
                        type = types.str;
                        default = "";
                        description = "Custom path for blackbox health checks (e.g., '/health'). Empty string means root path.";
                      };

                      allow40x = mkOption {
                        type = types.bool;
                        default = false;
                        description = "Whether to allow 4xx HTTP status codes in blackbox monitoring.";
                      };
                    };
                  };
                  default = { };
                  description = "Blackbox monitoring configuration for this virtual host.";
                };
              };
            }
          )
        );
        default = { };
        description = "Caddy virtual hosts with integrated blackbox configuration.";
      };
    };
  };

  config = mkIf (cfg.virtualHosts != { }) {
    # Configure the standard Caddy service with our virtual hosts
    services.caddy.virtualHosts = mapAttrs (hostname: vhost: {
      extraConfig = vhost.extraConfig;
      logFormat = null;
    }) cfg.virtualHosts;

    # Extract blackbox configuration for use by hostedUrls
    custom.blackboxConfig = {
      disabled = filter (x: x != null) (
        mapAttrsToList (
          hostname: vhost: if vhost.blackbox.disabled then hostname else null
        ) cfg.virtualHosts
      );

      paths = filterAttrs (hostname: path: path != "") (
        mapAttrs (hostname: vhost: vhost.blackbox.path) cfg.virtualHosts
      );

      allow40x = filter (x: x != null) (
        mapAttrsToList (
          hostname: vhost: if vhost.blackbox.allow40x then hostname else null
        ) cfg.virtualHosts
      );
    };
  };
}
