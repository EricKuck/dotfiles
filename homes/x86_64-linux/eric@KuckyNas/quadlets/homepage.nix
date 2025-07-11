{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/homepage";
in
{
  quadlets = {
    containers = {
      homepage = {
        containerConfig = {
          image = "ghcr.io/gethomepage/homepage:latest";
          name = "homepage";
          autoUpdate = "registry";
          environments = {
            PORT = "3010";
            HOMEPAGE_ALLOWED_HOSTS = "192.168.1.2:3010,homepage.kuck.ing";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/app/config"
            "/run/user/1000/podman/podman.sock:/var/run/podman.sock"
          ];
          publishPorts = [
            "${toString osConfig.ports.homepage}:3010"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=homepage.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
