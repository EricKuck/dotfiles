{
  config,
  lib,
  pkgs,
  ...
}:

let
  rules = [
    {
      groups = [
        {
          name = "system";
          rules = [
            {
              alert = "MonitoringDown";
              expr = "up == 0";
              annotations = {
                summary = "Monitoring process is down or unreachable";
                description = ''{{ $labels.instance }} not reachable.'';
              };
            }
          ];
        }
      ];
    }
  ];

  ruleFile = pkgs.writeTextFile {
    name = "prometheus-rules.yaml";
    text = lib.generators.toYAML { } (builtins.head rules);
  };
in
{
  imports = lib.fileset.toList (lib.fileset.fileFilter (file: file.name != "default.nix") ./.);

  users.users.loki.extraGroups = [ "caddy" ];

  sops.secrets.alertmanager_discord_webhook = {
    owner = "alertmanager";
    group = "alertmanager";
    mode = "0400";
  };

  services = {
    prometheus = {
      enable = true;
      port = config.ports.prometheus;
      retentionTime = "1y";
      globalConfig = {
        scrape_interval = "30s";
        scrape_timeout = "25s";
      };
      ruleFiles = [ ruleFile ];

      alertmanagers = [
        {
          static_configs = [
            {
              targets = [ "localhost:${toString config.ports.prometheus-alertmanager}" ];
            }
          ];
        }
      ];

      alertmanager = {
        enable = true;
        port = config.ports.prometheus-alertmanager;

        configuration = {
          global.resolve_timeout = "5m";

          route = {
            receiver = "discord";
            group_by = [
              "alertname"
              "instance"
            ];
            group_wait = "0s";
            group_interval = "1s";
            repeat_interval = "1h";
          };

          receivers = [
            {
              name = "discord";
              discord_configs = [
                {
                  webhook_url_file = config.sops.secrets.alertmanager_discord_webhook.path;
                }
              ];
            }
          ];
        };
      };
    };

    loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        analytics.reporting_enabled = false;
        server.http_listen_port = config.ports.loki;
        common = {
          ring = {
            instance_addr = "localhost";
            kvstore.store = "inmemory";
          };
          replication_factor = 1;
          path_prefix = "/tmp/loki";
        };
        schema_config = {
          configs = [
            {
              from = "2025-06-27";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };
        storage_config.filesystem.directory = "/var/lib/loki/chunks";
        limits_config.volume_enabled = true;
      };
      extraFlags = [
        "--pattern-ingester.enabled=true"
        "--server.http-listen-port=${toString config.ports.loki}"
        "--log.level=warn"
      ];
    };

    alloy = {
      enable = true;
      extraFlags = [
        "--server.http.listen-addr=localhost:${toString config.ports.alloy}"
        "--disable-reporting"
      ];
    };

    grafana = {
      enable = true;
      settings = {
        analytics.reporting_enabled = false;
        server = {
          domain = "grafana.kuck.ing";
          addr = "localhost";
          http_port = config.ports.grafana;
        };
      };

      provision.datasources.settings.datasources = [
        {
          name = "prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:${toString config.ports.prometheus}";
        }
        {
          name = "loki";
          type = "loki";
          access = "proxy";
          url = "http://localhost:${toString config.ports.loki}";
        }
      ];
    };
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.write "default" {
      endpoint {
        url = "http://localhost:${toString config.ports.loki}/loki/api/v1/push"
      }
    }

    // system journald
    discovery.relabel "systemd_journal" {
      targets = []

      rule {
        action        = "drop"
        source_labels = ["__journal__systemd_user_unit"]
        regex         = ".*"
      }

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "systemd_journal" {
      max_age       = "48h0m0s"
      forward_to    = [loki.write.default.receiver]
      relabel_rules = discovery.relabel.systemd_journal.rules
      labels        = {
        component = "systemd_journal",
      }
    }

    // user journald
    discovery.relabel "user_systemd_journal" {
      targets = []

      rule {
        source_labels = ["__journal__systemd_user_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "user_systemd_journal" {
      max_age       = "48h0m0s"
      forward_to    = [loki.write.default.receiver]
      relabel_rules = discovery.relabel.user_systemd_journal.rules
      labels        = {
        component = "user_systemd_journal",
      }
    }
  '';
}
