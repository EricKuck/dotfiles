{ config, pkgs, ... }:
let
  PORT = config.ports.prometheus-blackbox-exporter;

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
        targets = [ "localhost:${toString PORT}" ];
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
      containers = config.home-manager.users.eric.virtualisation.quadlet.containers;
    in
    builtins.concatLists (
      builtins.map (
        name:
        let
          labels = containers.${name}.containerConfig.labels or [ ];
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
  services.prometheus = {
    exporters = {
      blackbox = {
        enable = true;
        port = PORT;
        configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON blackboxConfig);
      };
    };

    scrapeConfigs = [
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
}
