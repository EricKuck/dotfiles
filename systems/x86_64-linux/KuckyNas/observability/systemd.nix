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

  environment.etc."alloy/config.alloy".text = ''
    discovery.relabel "systemd_journal" {
      targets = []

      rule {
        action        = "drop"
        source_labels = ["__journal__systemd_user_unit"]
        regex         = ".*"
      }

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "systemd_journal" {
      max_age       = "48h0m0s"
      forward_to    = [loki.write.default.receiver]
      relabel_rules = discovery.relabel.systemd_journal.rules
      labels        = {
        component = "systemd_journal",
      }
    }
  '';
}
