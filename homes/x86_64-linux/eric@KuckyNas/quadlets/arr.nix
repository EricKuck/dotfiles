{ config, osConfig, ... }:
let
  PROWLARR_CONTAINER_PATH = "${osConfig.meta.containerData}/prowlarr";
  SONARR_CONTAINER_PATH = "${osConfig.meta.containerData}/sonarr";
  RADARR_CONTAINER_PATH = "${osConfig.meta.containerData}/radarr";
  BAZARR_CONTAINER_PATH = "${osConfig.meta.containerData}/bazarr";
  PROFILARR_CONTAINER_PATH = "${osConfig.meta.containerData}/profilarr";
  CLEANUPARR_CONTAINER_PATH = "${osConfig.meta.containerData}/cleanuparr";
  HUNTARR_CONTAINER_PATH = "${osConfig.meta.containerData}/huntarr";
  MYLAR3_CONTAINER_PATH = "${osConfig.meta.containerData}/mylar3";
  TORRENT_DL_PATH = "${osConfig.meta.containerData}/qbittorrent/downloads";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  quadlets = {
    containers = {
      byparr = {
        containerConfig = {
          image = "ghcr.io/thephaseless/byparr:latest";
          name = "byparr";
          autoUpdate = "registry";
          publishPorts = [
            "${toString osConfig.ports.byparr}:8191"
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
          };
          volumes = [
            "${PROWLARR_CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.prowlarr}:9696"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=prowlarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [ containers.byparr.ref ];
          After = [ containers.byparr.ref ];
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
          };
          volumes = [
            "${SONARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/TV:/tv"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "${toString osConfig.ports.sonarr}:8989"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=sonarr.kuck.ing"
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
          };
          volumes = [
            "${RADARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/Movies:/movies"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "${toString osConfig.ports.radarr}:7878"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=radarr.kuck.ing"
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
          };
          volumes = [
            "${BAZARR_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/TV:/tv"
            "/kuckyjar/media/Movies:/movies"
          ];
          publishPorts = [
            "${toString osConfig.ports.bazarr}:6767"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=bazarr.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      profilarr = {
        containerConfig = {
          image = "docker.io/santiagosayshey/profilarr:latest";
          name = "profilarr";
          autoUpdate = "registry";
          volumes = [
            "${PROFILARR_CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.profilarr}:6868"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=profilarr.kuck.ing"
          ];
          user = osConfig.serviceOwners.profilarr;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      cleanuparr = {
        containerConfig = {
          image = "ghcr.io/cleanuparr/cleanuparr:latest";
          name = "cleanuparr";
          autoUpdate = "registry";
          volumes = [
            "${CLEANUPARR_CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.cleanuparr}:11011"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=cleanuparr.kuck.ing"
          ];
          user = osConfig.serviceOwners.cleanuparr;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      huntarr = {
        containerConfig = {
          image = "ghcr.io/plexguide/huntarr:latest";
          name = "huntarr";
          autoUpdate = "registry";
          volumes = [
            "${HUNTARR_CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.huntarr}:9705"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=huntarr.kuck.ing"
          ];
          user = osConfig.serviceOwners.huntarr;
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
          };
          volumes = [
            "${MYLAR3_CONTAINER_PATH}/config:/config"
            "/kuckyjar/media/Comics:/comics"
            "${TORRENT_DL_PATH}:/downloads"
          ];
          publishPorts = [
            "${toString osConfig.ports.mylar3}:8090"
          ];
          networks = [ networks.wireguard.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=mylar3.kuck.ing"
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
