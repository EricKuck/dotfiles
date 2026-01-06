{ config, osConfig, ... }:
let
  BOOKLORE_CONTAINER_PATH = "${osConfig.meta.containerData}/booklore";
  EPHEMERA_CONTAINER_PATH = "${osConfig.meta.containerCache}/ephemera";
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
            "${BOOKLORE_CONTAINER_PATH}/data:/app/data"
            "/kuckyjar/media/Books:/books"
            "${BOOKLORE_CONTAINER_PATH}/bookdrop:/bookdrop"
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
            "${BOOKLORE_CONTAINER_PATH}/db:/config"
          ];
          networks = [ networks.booklore.ref ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      # TODO: remove once byparr has ephemera support
      flaresolverr = {
        containerConfig = {
          image = "ghcr.io/flaresolverr/flaresolverr:latest";
          name = "flaresolverr";
          autoUpdate = "registry";
          environments = {
            PORT = toString osConfig.ports.flaresolverr;
          };
          publishPorts = [
            "${toString osConfig.ports.flaresolverr}:${toString osConfig.ports.flaresolverr}"
          ];
          networks = [ networks.booklore.ref ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      ephemera = {
        containerConfig = {
          image = "ghcr.io/orwellianepilogue/ephemera:latest";
          name = "ephemera";
          autoUpdate = "registry";
          environments = {
            AA_BASE_URL = "https://annas-archive.se";
            LG_BASE_URL = "https://libgen.bz";
            FLARESOLVERR_URL = "http://host.containers.internal:${toString osConfig.ports.flaresolverr}";
          };
          volumes = [
            "${EPHEMERA_CONTAINER_PATH}/data:/app/data"
            "${EPHEMERA_CONTAINER_PATH}/downloads:/app/downloads"
            "${BOOKLORE_CONTAINER_PATH}/bookdrop:/app/ingest"
          ];
          publishPorts = [
            "${toString osConfig.ports.ephemera}:8286"
          ];
          networks = [ networks.booklore.ref ];
          labels = [
            "caddy.enable=true"
            "caddy.host=ephemera.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
