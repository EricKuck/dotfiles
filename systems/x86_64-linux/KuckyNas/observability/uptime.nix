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
          method = "GET";
          fail_if_not_ssl = false;
        };
      };

      https_2xx = {
        prober = "http";
        timeout = "5s";
        http = {
          method = "GET";
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

  directCaddyUrls = builtins.filter (item: builtins.match ".*\\*.*" item == null) (
    builtins.attrNames config.services.caddy.virtualHosts
  );

  containerUrls =
    let
      containers = config.home-manager.users."${config.meta.flake.owner}".quadlets.containers;
    in
    builtins.concatLists (
      builtins.map (
        name:
        let
          rawLabels = containers.${name}.containerConfig.labels or [ ];
          labels = if builtins.isAttrs rawLabels then builtins.attrValues rawLabels else rawLabels;
        in
        builtins.map
          (
            label:
            let
              parts = builtins.match "([^=]+)=(.*)" label;
            in
            builtins.elemAt parts 1
          )
          (
            builtins.filter (
              label:
              let
                parts = builtins.match "([^=]+)=(.*)" label;
              in
              parts != null && builtins.match "caddy.host" (builtins.elemAt parts 0) != null
            ) labels
          )
      ) (builtins.attrNames containers)
    );

  caddyUrls = builtins.map (item: "https://${item}") (directCaddyUrls ++ containerUrls);
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
          targets = caddyUrls;
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
      execStart = "${lib.getExe pkgs.prometheus-blackbox-exporter} --web.listen-address localhost:${toString config.ports.prometheus-blackbox-exporter} --config.file ${configFile}";
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
