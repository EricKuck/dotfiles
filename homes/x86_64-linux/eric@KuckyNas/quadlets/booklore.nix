{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/booklore";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  quadlets = {
    networks.booklore.networkConfig.driver = "bridge";
    containers = {
      booklore = {
        containerConfig = {
          image = "docker.io/booklore/booklore:latest";
          name = "booklore";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            DATABASE_URL = "jdbc:mariadb://booklore-db:3306/booklore";
            DATABASE_USERNAME = "booklore";
            BOOKLORE_PORT = toString osConfig.ports.booklore;
            SWAGGER_ENABLED = "false";
          };
          environmentFiles = [ osConfig.sops.secrets.booklore_env.path ];
          volumes = [
            "${CONTAINER_PATH}/data:/app/data"
            "/kuckyjar/media/Books:/books"
            "${CONTAINER_PATH}/bookdrop:/bookdrop"
          ];
          publishPorts = [
            "${toString osConfig.ports.booklore}:${toString osConfig.ports.booklore}"
          ];
          networks = [ networks.booklore.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=booklore.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [ containers.booklore-db.ref ];
          After = [ containers.booklore-db.ref ];
        };
      };

      booklore-db = {
        containerConfig = {
          image = "lscr.io/linuxserver/mariadb:11.4.5";
          name = "booklore-db";
          healthCmd = "mariadb-admin ping -h localhost";
          healthInterval = "5s";
          healthRetries = 10;
          healthTimeout = "5s";
          environments = {
            PUID = "1072";
            PGID = "1072";
            MYSQL_DATABASE = "booklore";
            MYSQL_USER = "booklore";
          };
          environmentFiles = [ osConfig.sops.secrets.booklore-db_env.path ];
          volumes = [
            "${CONTAINER_PATH}/db:/config"
          ];
          networks = [ networks.booklore.ref ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      calibre-downloader = {
        containerConfig = {
          image = "ghcr.io/calibrain/calibre-web-automated-book-downloader-extbp:latest";
          name = "calibre-web-downloader";
          autoUpdate = "registry";
          environments = {
            USE_BOOK_TITLE = "true";
            EXT_BYPASSER_URL = "http://host.containers.internal:${toString osConfig.ports.byparr}";
          };
          volumes = [
            "${CONTAINER_PATH}/bookdrop:/cwa-book-ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.calibre-downloader}:8084"
          ];
          networks = [ networks.booklore.ref ];
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
