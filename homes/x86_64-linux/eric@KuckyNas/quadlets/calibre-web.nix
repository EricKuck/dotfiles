{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/calibre-web";
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
    };
  };
}
