{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/scrypted";
in
{
  quadlets = {
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
