{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/freshrss";
in
{
  virtualisation.quadlet = {
    containers = {
      freshrss = {
        containerConfig = {
          image = "lscr.io/linuxserver/freshrss:latest";
          name = "freshrss";
          autoUpdate = "registry";
          environments = {
            PUID = "1240";
            PGID = "1240";
            TZ = "America/New_York";
            DOCKER_MODS = "linuxserver/mods:universal-cron";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.freshrss}:80"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=freshrss.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
