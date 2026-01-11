{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-blackbox-exporter;

  blackboxConfig = {
    modules = {
      http_2xx = {
        prober = "http";
        timeout = "5s";
        http = {
          preferred_ip_protocol = "ip4";
          method = "GET";
          fail_if_not_ssl = false;
        };
      };

      https_2xx = {
        prober = "http";
        timeout = "5s";
        http = {
          preferred_ip_protocol = "ip4";
          method = "GET";
          fail_if_not_ssl = true;
        };
      };

      https_2xx_or_40x = {
        prober = "http";
        timeout = "5s";
        http = {
          preferred_ip_protocol = "ip4";
          method = "GET";
          valid_status_codes = [
            200
            201
            202
            203
            204
            205
            206
            400
            401
            403
            404
          ];
          fail_if_not_ssl = true;
        };
      };

      icmp = {
        prober = "icmp";
        timeout = "5s";
      };
    };
  };

  configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON blackboxConfig);

  blackboxTargets =
    {
      job_name,
      scrape_interval,
      modules,
      targets,
    }:
    {
      job_name = job_name;
      scrape_interval = scrape_interval;
      metrics_path = "/probe";
      params = {
        module = modules;
      };
      static_configs = map (t: {
        targets = [ "localhost:${toString port}" ];
        labels.target = t;
      }) targets;
      relabel_configs = [
        {
          source_labels = [ "target" ];
          target_label = "__param_target";
        }
      ];
    };

  caddyUrls = lib.custom.hostedUrls {
    inherit config;
    forBlackbox = true;
  };
in
{
  services.custom.prometheus-exporters.blackbox = {
    enable = true;
    port = config.ports.prometheus-blackbox-exporter;
    scrape = {
      interval = null;
      configs = [
        (blackboxTargets {
          job_name = "http_probe";
          scrape_interval = "1m";
          modules = [ "http_2xx" ];
          targets = [ "http://192.168.1.1" ];
        })

        (blackboxTargets {
          job_name = "https_probe";
          scrape_interval = "1m";
          modules = [ "https_2xx" ];
          targets = builtins.map (x: x.url) caddyUrls.strict;
        })

        (blackboxTargets {
          job_name = "https_probe_40x";
          scrape_interval = "1m";
          modules = [ "https_2xx_or_40x" ];
          targets = builtins.map (x: x.url) caddyUrls.allow40x;
        })

        (blackboxTargets {
          job_name = "icmp_probe";
          scrape_interval = "15s";
          modules = [ "icmp" ];
          targets = [
            "192.168.1.1"
            "1.1.1.1"
            "8.8.8.8"
          ];
        })
      ];
    };
    systemd = {
      ambientCapabilities = [ "CAP_NET_RAW" ];
      execStart = "${lib.getExe pkgs.prometheus-blackbox-exporter} --web.listen-address localhost:${toString config.ports.prometheus-blackbox-exporter} --config.file ${configFile} --log.level=info --log.prober=info";
      execReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
    };
    rules = [
      {
        name = "uptime";
        rules = [
          {
            alert = "ServiceOutage";
            expr = ''probe_success{job!="icmp_probe"} == 0'';
            annotations = {
              summary = "Service probe failed";
              description = ''Failed on {{ $labels.target }}'';
            };
          }
        ];
      }
      {
        name = "certs";
        rules = [
          {
            alert = "CertExpiration";
            expr = "0 <= round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 3";
            annotations = {
              summary = "SSL cert will expire soon";
              description = ''Will expire for {{ $labels.target }}'';
            };
          }
        ];
      }
    ];
  };
}
