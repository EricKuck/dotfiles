{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/homepage";
in
{
  virtualisation.quadlet = {
    containers = {
      homepage = {
        containerConfig = {
          image = "ghcr.io/gethomepage/homepage:latest";
          name = "homepage";
          autoUpdate = "registry";
          environments = {
            PORT = "3010";
            HOMEPAGE_ALLOWED_HOSTS = "192.168.1.2:3010";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/app/config"
            "/run/user/1000/podman/podman.sock:/var/run/podman.sock"
          ];
          publishPorts = [
            "3010:3010"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
