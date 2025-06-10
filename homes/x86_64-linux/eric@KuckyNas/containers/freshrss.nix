{ config, ... }:
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
            "8487:80"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
