{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/syncthing";
in
{
  virtualisation.quadlet = {
    containers = {
      syncthing = {
        containerConfig = {
          image = "lscr.io/linuxserver/syncthing:latest";
          name = "syncthing";
          autoUpdate = "registry";
          environments = {
            PGID = "1008";
            PUID = "1008";
            TZ = "America/New_York";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/data:/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.syncthing}:8384/tcp"
            "${toString osConfig.ports.syncthing_discovery}:21027/udp"
            "${toString osConfig.ports.syncthing_sync}:22000/tcp"
            "${toString osConfig.ports.syncthing_sync}:22000/udp"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.syncthing}"
            "caddy.host=syncthing.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
