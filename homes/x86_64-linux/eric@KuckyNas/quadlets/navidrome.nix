{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/navidrome";
in
{
  quadlets = {
    containers = {
      navidrome = {
        containerConfig = {
          image = "docker.io/deluan/navidrome:latest";
          name = "navidrome";
          autoUpdate = "registry";
          volumes = [
            "${CONTAINER_PATH}/data:/data"
            "/kuckyjar/media/Music:/music"
          ];
          publishPorts = [
            "${toString osConfig.ports.navidrome}:4533"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=navidrome.kuck.ing"
          ];
          user = osConfig.serviceOwners.arr;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
