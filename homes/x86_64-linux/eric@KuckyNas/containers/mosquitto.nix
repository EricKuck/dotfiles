{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/mosquitto";
in
{
  virtualisation.quadlet = {
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
            "1883:1883"
            "9001:9001"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
