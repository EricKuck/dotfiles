{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-mqtt-exporter;
  name = "mqtt-exporter";

  rules = [
    {
      groups = [
        {
          name = "mqtt";
          rules = [
            {
              alert = "ZigbeeDeviceUnavailable";
              expr = ''mqtt_zigbee_availability == 0'';
              for = "1m";
              labels = {
                no_repeat = true;
              };
              annotations = {
                summary = "Zigbee device has become unavailable";
                description = ''Device topic: {{ $labels.topic }}'';
              };
            }
          ];
        }
      ];
    }
  ];

  ruleFile = pkgs.writeTextFile {
    name = "mqtt-rules.yaml";
    text = lib.generators.toYAML { } (builtins.head rules);
  };
in
{
  users = {
    users."${name}" = {
      isSystemUser = true;
      group = name;
    };

    groups."${name}" = { };
  };

  sops.secrets.mqtt_exporter_env.owner = name;

  services.prometheus = {
    exporters = {
      mqtt = {
        enable = true;
        port = port;
        zigbee2MqttAvailability = true;
        mqttUsername = "prometheus";
        environmentFile = config.sops.secrets.mqtt_exporter_env.path;
      };
    };

    scrapeConfigs = [
      {
        job_name = "mqtt";
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
