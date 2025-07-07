{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.quadlet = {
    enable = true;
    port = config.ports.prometheus-quadlet-exporter;
    systemd = {
      isUserService = true;
      execStart = "${lib.getExe pkgs.custom.prometheus-quadlet-exporter} --port ${toString config.ports.prometheus-quadlet-exporter}";
    };
  };
}
