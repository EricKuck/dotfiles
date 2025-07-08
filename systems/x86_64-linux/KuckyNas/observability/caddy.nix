{ config, ... }:
{
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "caddy" ];
  users.users.loki.extraGroups = [ "caddy" ];

  environment.etc."alloy/config.alloy".text = ''
    local.file_match "caddy_access_log" {
      path_targets = [
        {
          "__path__" = "/var/log/caddy/access.log",
        },
      ]
      sync_period = "5s"
    }

    loki.source.file "caddy_access_log" {
      targets = local.file_match.caddy_access_log.targets
      forward_to = [loki.process.caddy_access_log.receiver]
    }

    loki.process "caddy_access_log" {
      forward_to = [loki.write.default.receiver]

      stage.json {
        expressions = {
          level = "",
          host = "request.host",
          method = "request.method",
          proto = "request.proto",
          ts = "",
        }
      }

      stage.labels {
        values = {
          level = "",
          host = "",
          method = "",
          proto = "",
        }
      }

      stage.label_drop {
        values = ["service_name"]
      }

      stage.static_labels {
        values = {
          job = "caddy_access_log",
        }
      }

      stage.timestamp {
        source = "ts"
        format = "unix"
      }
    }
  '';
}
