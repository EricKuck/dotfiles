{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-systemd-exporter;

  rules = [
    {
      groups = [
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
    }
  ];

  ruleFile = pkgs.writeTextFile {
    name = "systemd-rules.yaml";
    text = lib.generators.toYAML { } (builtins.head rules);
  };
in
{
  services.prometheus = {
    exporters = {
      systemd = {
        enable = true;
        port = port;
      };
    };

    scrapeConfigs = [
      {
        job_name = "systemd";
        scrape_interval = "10s";
        static_configs = [
          {
            targets = [ "localhost:${toString port}" ];
          }
        ];
      }
    ];

    ruleFiles = [ ruleFile ];
  };
}
