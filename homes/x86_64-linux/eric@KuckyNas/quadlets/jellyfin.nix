{ config, osConfig, ... }:
let
  FIN_CONTAINER_PATH = "${osConfig.meta.containerData}/jellyfin";
  SEER_CONTAINER_PATH = "${osConfig.meta.containerData}/jellyseer";
  RECOMMEND_CONTAINER_PATH = "${osConfig.meta.containerData}/recommendarr";
  SUGGEST_CONTAINER_PATH = "${osConfig.meta.containerData}/suggestarr";
in
{
  quadlets = {
    containers = {
      jellyfin = {
        containerConfig = {
          image = "lscr.io/linuxserver/jellyfin:latest";
          name = "jellyfin";
          autoUpdate = "registry";
          environments = {
            VIRTUAL_ENV = "/lsiopy";
            LSIO_FIRST_PARTY = "true";
            NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
            JELLYFIN_PublishedServerUrl = "192.168.1.2";
            PUID = toString osConfig.uids.jellyfin;
            PGID = toString osConfig.uids.jellyfin;
          };
          volumes = [
            "${FIN_CONTAINER_PATH}/config:/config"
            "${FIN_CONTAINER_PATH}/cache:/cache"
            "/kuckyjar/media:/media:ro"
          ];
          publishPorts = [
            "${toString osConfig.ports.jellyfin}:8096"
          ];
          devices = [ "/dev/dri:/dev/dri" ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.jellyfin}"
            "caddy.host=jellyfin.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      jellyseerr = {
        containerConfig = {
          image = "docker.io/fallenbagel/jellyseerr:latest";
          name = "jellyseerr";
          autoUpdate = "registry";
          volumes = [
            "${SEER_CONTAINER_PATH}/config:/app/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.jellyseerr}:5055"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=jellyseerr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      recommendarr = {
        containerConfig = {
          image = "docker.io/tannermiddleton/recommendarr:latest";
          name = "recommendarr";
          autoUpdate = "registry";
          volumes = [
            "${RECOMMEND_CONTAINER_PATH}/data:/app/server/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.recommendarr}:3000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=recommendarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      suggestarr = {
        containerConfig = {
          image = "docker.io/ciuse99/suggestarr:latest";
          name = "suggestarr";
          autoUpdate = "registry";
          volumes = [
            "${SUGGEST_CONTAINER_PATH}/config:/app/config/config_files"
          ];
          publishPorts = [
            "${toString osConfig.ports.suggestarr}:5000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=suggestarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
