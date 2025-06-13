{ config, osConfig, ... }:
let
  FIN_CONTAINER_PATH = "/kuckyjar/container/jellyfin";
  SEER_CONTAINER_PATH = "/kuckyjar/container/jellyseer";
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
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.upstream.port=8096"
            "com.caddyserver.http.matchers.host=jellyfin.kuck.ing"
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
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=jellyseerr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
