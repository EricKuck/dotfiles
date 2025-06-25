{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = lib.fileset.toList (lib.fileset.fileFilter (file: file.name != "default.nix") ./.);

  services = {
    prometheus = {
      enable = true;
      port = config.ports.prometheus;
      globalConfig.scrape_interval = "30s";
      globalConfig.scrape_timeout = "25s";
    };

    grafana = {
      enable = true;
      settings = {
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
      ];
    };
  };
}
