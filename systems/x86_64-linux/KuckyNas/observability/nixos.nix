{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.nixos = {
    enable = true;
    port = config.ports.prometheus-nixos-exporter;
    scrape.interval = "1m";
    systemd = {
      path = [
        pkgs.nix
        pkgs.bash
      ];
      execStart = "${lib.getExe pkgs.custom.prometheus-nixos-exporter} --port ${toString config.ports.prometheus-nixos-exporter}";
    };
  };
}
