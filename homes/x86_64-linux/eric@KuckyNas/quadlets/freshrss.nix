{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/freshrss";
in
{
  quadlets = {
    containers = {
      freshrss = {
        containerConfig = {
          image = "lscr.io/linuxserver/freshrss:latest";
          name = "freshrss";
          autoUpdate = "registry";
          environments = {
            PUID = toString osConfig.uids.freshrss;
            PGID = toString osConfig.uids.freshrss;
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
