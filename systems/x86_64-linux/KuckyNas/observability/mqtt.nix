{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.mqtt = {
    enable = true;
    port = config.ports.prometheus-mqtt-exporter;
    systemd = {
      execStart = lib.getExe pkgs.mqtt-exporter;
      environment = {
        MQTT_USERNAME = "prometheus";
        PROMETHEUS_PORT = toString config.ports.prometheus-mqtt-exporter;
        ZIGBEE2MQTT_AVAILABILITY = "true";
      };
      environmentFile = config.sops.secrets.mqtt_exporter_env.path;
    };
    rules = [
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
  };

  sops.secrets.mqtt_exporter_env.owner =
    config.services.custom.prometheus-exporters.mqtt.systemd.user;
}
