{ config, ... }:
let
  PORT = config.ports.prometheus-unifi-exporter;
in
{
  users = {
    users.unifi = {
      isSystemUser = true;
      group = "unifi";
    };

    groups.unifi = { };
  };

  sops.secrets.unifi_pw.owner = "unifi";

  services.prometheus = {
    exporters = {
      unpoller = {
        enable = true;
        port = PORT;
        user = "unifi";
        controllers = [
          {
            url = "https://localhost:8443";
            user = "prometheus";
            pass = config.sops.secrets.unifi_pw.path;
            verify_ssl = false;
            save_ids = true;
            save_events = true;
            save_anomalies = true;
            save_alarms = true;
          }
        ];
      };
    };

    scrapeConfigs = [
      {
        job_name = "unifi";
        scrape_interval = "10s";
        static_configs = [
          {
            targets = [ "localhost:${toString PORT}" ];
          }
        ];
      }
    ];
  };
}
