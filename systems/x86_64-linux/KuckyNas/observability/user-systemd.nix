{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.user-systemd = {
    enable = true;
    port = config.ports.prometheus-user-systemd-exporter;
    systemd = {
      isUserService = true;
      execStart = "${lib.getExe pkgs.prometheus-systemd-exporter} --web.listen-address localhost:${toString config.ports.prometheus-user-systemd-exporter} --systemd.collector.user";
    };
  };
}
