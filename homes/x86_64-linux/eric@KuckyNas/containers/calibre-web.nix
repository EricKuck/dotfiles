{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/calibre-web";
  M_CONTAINER_PATH = "/kuckyjar/container/calibre-web-m";
  inherit (config.virtualisation.quadlet) networks;
in
{
  quadlets = {
    networks.calibre.networkConfig.driver = "bridge";
    containers = {
      calibre = {
        containerConfig = {
          image = "docker.io/crocodilestick/calibre-web-automated:latest";
          name = "calibre-web-automated";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/library:/calibre-library"
            "${CONTAINER_PATH}/ingest:/cwa-book-ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.calibre}:8083"
          ];
          networks = [ networks.calibre.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=calibre.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      calibre-m = {
        containerConfig = {
          image = "docker.io/crocodilestick/calibre-web-automated:latest";
          name = "calibre-web-automated-m";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
          };
          volumes = [
            "${M_CONTAINER_PATH}/config:/config"
            "${M_CONTAINER_PATH}/library:/calibre-library"
            "${M_CONTAINER_PATH}/ingest:/cwa-book-ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.calibre-m}:8083"
          ];
          networks = [ networks.calibre.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=calibre-m.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      calibre-downloader = {
        containerConfig = {
          image = "ghcr.io/calibrain/calibre-web-automated-book-downloader:latest";
          name = "calibre-web-downloader";
          autoUpdate = "registry";
          environments = {
            USE_BOOK_TITLE = "true";
          };
          volumes = [
            "${CONTAINER_PATH}/ingest:/cwa-book-ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.calibre-downloader}:8084"
          ];
          networks = [ networks.calibre.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=calibre-downloader.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      calibre-downloader-m = {
        containerConfig = {
          image = "ghcr.io/calibrain/calibre-web-automated-book-downloader:latest";
          name = "calibre-web-downloader-m";
          autoUpdate = "registry";
          environments = {
            USE_BOOK_TITLE = "true";
          };
          volumes = [
            "${M_CONTAINER_PATH}/ingest:/cwa-book-ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.calibre-downloader-m}:8084"
          ];
          networks = [ networks.calibre.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=calibre-downloader-m.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
