{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/changedetection";
in
{
  quadlets = {
    containers = {
      changedetection = {
        containerConfig = {
          image = "docker.io/dgtlmoon/changedetection.io:latest";
          name = "changedetection";
          autoUpdate = "registry";
          environments = {
            BASE_URL = "https://change.kuck.ing";
          };
          volumes = [
            "${CONTAINER_PATH}/data:/datastore"
          ];
          publishPorts = [
            "${toString osConfig.ports.changedetection}:5000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=change.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
