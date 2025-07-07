{
  config,
  lib,
  pkgs,
  ...
}:
let
  configFile = pkgs.writeText "prometheus-unpoller-exporter.json" (
    lib.generators.toJSON { } {
      influxdb.disable = true;
      datadog.disable = true;
      poller = {
        debug = false;
        quiet = false;
      };
      unifi = {
        controllers = [
          {
            url = "https://localhost:${toString config.ports.unifi}";
            user = "prometheus";
            pass = "file://${config.sops.secrets.unifi_pw.path}";
            save_ids = true;
            save_events = true;
            save_alarms = true;
            save_anomalies = true;
          }
        ];
      };
      prometheus = {
        http_listen = "localhost:${toString config.ports.prometheus-unifi-exporter}";
        report_errors = false;
      };
      loki.url = "localhost:${toString config.ports.loki}";
    }
  );
in
{
  services.custom.prometheus-exporters.unifi = {
    enable = true;
    port = config.ports.prometheus-unifi-exporter;
    systemd.execStart = "${lib.getExe' pkgs.unpoller "unpoller"} --config ${configFile}";
  };

  sops.secrets.unifi_pw.owner = config.services.custom.prometheus-exporters.unifi.systemd.user;
}
