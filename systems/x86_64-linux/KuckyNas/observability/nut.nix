{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-nut-exporter;

  rules = [
    {
      groups = [
        {
          name = "power";
          rules = [
            {
              alert = "PowerOutage";
              expr = ''network_ups_tools_ups_status{flag="OL"} == 0'';
              annotations = {
                summary = "UPS no longer on line";
              };
            }
            {
              alert = "UPSLowBattery";
              expr = ''network_ups_tools_ups_status{flag="LB"} == 1'';
              annotations = {
                summary = "UPS low battery";
              };
            }
          ];
        }
      ];
    }
  ];

  ruleFile = pkgs.writeTextFile {
    name = "nut-rules.yaml";
    text = lib.generators.toYAML { } (builtins.head rules);
  };
in
{
  services.prometheus = {
    exporters = {
      nut = {
        enable = true;
        user = "upsmon";
        group = "upsmon";
        nutUser = config.users.users.upsmon.name;
        passwordPath = config.sops.secrets.upsmon_user_pw.path;
        port = port;
      };
    };

    scrapeConfigs = [
      {
        job_name = "nut";
        scrape_interval = "10s";
        metrics_path = "/ups_metrics";
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
