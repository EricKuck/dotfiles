{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/sabnzbd";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  quadlets = {
    containers = {
      sabnzbd = {
        containerConfig = {
          image = "lscr.io/linuxserver/sabnzbd:latest";
          name = "sabnzbd";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            UMASK = "022";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/downloads:/nzb_downloads"
            "${CONTAINER_PATH}/incomplete:/incomplete-downloads"
          ];
          publishPorts = [
            "${toString osConfig.ports.sabnzbd}:8080"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.sabnzbd}"
            "caddy.host=sabnzbd.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
