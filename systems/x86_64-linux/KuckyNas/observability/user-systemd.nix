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

  environment.etc."alloy/config.alloy".text = ''
    discovery.relabel "user_systemd_journal" {
      targets = []

      rule {
        source_labels = ["__journal__systemd_user_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "user_systemd_journal" {
      max_age       = "48h0m0s"
      forward_to    = [loki.write.default.receiver]
      relabel_rules = discovery.relabel.user_systemd_journal.rules
      labels        = {
        component = "user_systemd_journal",
      }
    }
  '';
}
