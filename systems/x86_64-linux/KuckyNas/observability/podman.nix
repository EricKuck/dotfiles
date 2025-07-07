{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.podman = {
    enable = true;
    port = config.ports.prometheus-podman-exporter;
    systemd = {
      execStart = "${lib.getExe pkgs.custom.prometheus-podman-exporter} --web.listen-address localhost:${toString config.ports.prometheus-podman-exporter} --collector.image";
      extraUserGroups = [ "podman" ];
    };
  };
}
