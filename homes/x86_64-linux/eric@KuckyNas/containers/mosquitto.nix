{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/mosquitto";
in
{
  quadlets = {
    containers = {
      mosquitto = {
        containerConfig = {
          image = "docker.io/eclipse-mosquitto:latest";
          name = "mosquitto";
          autoUpdate = "registry";
          volumes = [
            "${CONTAINER_PATH}/config/passwordfile:/mosquitto/config/passwordfile"
            "${CONTAINER_PATH}/log:/mosquitto/log"
            "${CONTAINER_PATH}/data/:/mosquitto/data"
            "${CONTAINER_PATH}/config/mosquitto.conf:/mosquitto/config/mosquitto.conf"
          ];
          publishPorts = [
            "${toString osConfig.ports.mosquitto_mqtt}:1883"
            "${toString osConfig.ports.mosquitto_mqtt-websockets}:9001"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
