{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/syncthing";
in
{
  quadlets = {
    containers = {
      syncthing = {
        containerConfig = {
          image = "lscr.io/linuxserver/syncthing:latest";
          name = "syncthing";
          autoUpdate = "registry";
          environments = {
            PUID = toString osConfig.uids.syncthing;
            PGID = toString osConfig.uids.syncthing;
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
