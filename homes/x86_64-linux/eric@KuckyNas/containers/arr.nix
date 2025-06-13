{ config, ... }:
let
  PROWLARR_CONTAINER_PATH = "/kuckyjar/container/prowlarr";
  SONARR_CONTAINER_PATH = "/kuckyjar/container/sonarr";
  RADARR_CONTAINER_PATH = "/kuckyjar/container/radarr";
  BAZARR_CONTAINER_PATH = "/kuckyjar/container/bazarr";
  MYLAR3_CONTAINER_PATH = "/kuckyjar/container/mylar3";
  TORRENT_DL_PATH = "/kuckyjar/container/qbittorrent/downloads";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  virtualisation.quadlet = {
    containers = {
      flaresolverr = {
        containerConfig = {
          image = "ghcr.io/flaresolverr/flaresolverr:latest";
          name = "flaresolverr";
          autoUpdate = "registry";
          publishPorts = [
            "8191:8191"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      prowlarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/prowlarr:latest";
          name = "prowlarr";
          autoUpdate = "registry";
          environments = {
            PUID = "1044";
            PGID = "1044";
            TZ = "America/New_York";
          };
          volumes = [
            "${PROWLARR_CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "9696:9696"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=prowlarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [ containers.flaresolverr.ref ];
          After = [ containers.flaresolverr.ref ];
        };
      };

      sonarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/sonarr:latest";
          name = "sonarr";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            TZ = "America/New_York";
          };
          volumes = [
            "${SONARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/TV:/tv"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "8989:8989"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=sonarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
          After = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
        };
      };

      radarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/radarr:latest";
          name = "radarr";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            TZ = "America/New_York";
          };
          volumes = [
            "${RADARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/Movies:/movies"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "7878:7878"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=radarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
          After = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
        };
      };

      bazarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/bazarr:latest";
          name = "bazarr";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            TZ = "America/New_York";
          };
          volumes = [
            "${BAZARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/TV:/tv"
            "/kuckyjar/media/Movies:/movies"
          ];
          publishPorts = [
            "6767:6767"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=bazarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      mylar3 = {
        containerConfig = {
          image = "lscr.io/linuxserver/mylar3:latest";
          name = "mylar3";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            TZ = "America/New_York";
          };
          volumes = [
            "${MYLAR3_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/Comics:/comics"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "8090:8090"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=mylar3.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
          After = [
            containers.qbittorrent.ref
            containers.prowlarr.ref
          ];
        };
      };
    };
  };
}
