{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.systemd = {
    enable = true;
    port = config.ports.prometheus-systemd-exporter;
    systemd.execStart = "${lib.getExe pkgs.prometheus-systemd-exporter} --web.listen-address localhost:${toString config.ports.prometheus-systemd-exporter}";
    rules = [
      {
        name = "systemd";
        rules = [
          {
            alert = "UnitFailure";
            expr = ''systemd_unit_state{state="failed"} > 0'';
            annotations = {
              summary = "Systemd unit failed";
              description = ''{{ $labels.name }}'';
            };
          }
        ];
      }
    ];
  };
}
