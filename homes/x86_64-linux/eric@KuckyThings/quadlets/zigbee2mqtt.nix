{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/zigbee2mqtt";
in
{
  quadlets = {
    containers = {
      zigbee2mqtt = {
        containerConfig = {
          image = "docker.io/koenkk/zigbee2mqtt:latest";
          name = "zigbee2mqtt";
          autoUpdate = "registry";
          volumes = [
            "${CONTAINER_PATH}/data:/app/data"
            "/run/udev:/run/udev:ro"
          ];
          publishPorts = [
            "8080:8080"
          ];
          devices = [
            "/dev/ttyUSB0"
          ];
          addGroups = [
            "keep-groups"
          ];
          userns = "keep-id";
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
