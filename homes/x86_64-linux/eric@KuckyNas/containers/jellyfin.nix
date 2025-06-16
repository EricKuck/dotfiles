{ config, osConfig, ... }:
let
  FIN_CONTAINER_PATH = "/kuckyjar/container/jellyfin";
  SEER_CONTAINER_PATH = "/kuckyjar/container/jellyseer";
  RECOMMEND_CONTAINER_PATH = "/kuckyjar/container/recommendarr";
  SUGGEST_CONTAINER_PATH = "/kuckyjar/container/suggestarr";
in
{
  virtualisation.quadlet = {
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
            PGID = "1004";
            PUID = "1004";
            JELLYFIN_PublishedServerUrl = "192.168.1.2";
            TZ = "America/New_York";
          };
          volumes = [
            "${FIN_CONTAINER_PATH}/config:/config"
            "${FIN_CONTAINER_PATH}/cache:/cache"
            "/kuckyjar/media:/media:ro"
          ];
          publishPorts = [
            "8096:8096"
            "8920:8920"
          ];
          devices = [ "/dev/dri:/dev/dri" ];
          labels = [
            "caddy.enable=true"
            "caddy.port=8096"
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
          environments = {
            TZ = "America/New_York";
          };
          volumes = [
            "${SEER_CONTAINER_PATH}/config:/app/config"
          ];
          publishPorts = [
            "5055:5055"
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
          environments = {
            TZ = "America/New_York";
          };
          volumes = [
            "${RECOMMEND_CONTAINER_PATH}/data:/app/server/data"
          ];
          publishPorts = [
            "3033:3000"
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
          environments = {
            TZ = "America/New_York";
          };
          volumes = [
            "${SUGGEST_CONTAINER_PATH}/config:/app/config/config_files"
          ];
          publishPorts = [
            "3034:5000"
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
