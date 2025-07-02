{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/scrypted";
in
{
  virtualisation.quadlet = {
    containers = {
      scrypted = {
        containerConfig = {
          image = "docker.io/koush/scrypted:latest";
          name = "scrypted";
          autoUpdate = "registry";
          networks = [ "host" ];
          volumes = [
            "${CONTAINER_PATH}/volume:/server/volume"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
