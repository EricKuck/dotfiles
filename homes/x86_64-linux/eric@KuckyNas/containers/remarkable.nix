{ config, osConfig, ... }:
let
  RMCLOUD_CONTAINER_PATH = "/kuckyjar/container/rmfakecloud";
  PAPERLESS_CONTAINER_PATH = "/kuckyjar/container/paperless";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  quadlets = {
    networks.paperless.networkConfig.driver = "bridge";

    pods.paperless = { };

    containers = {
      rmfakecloud = {
        containerConfig = {
          image = "docker.io/ddvk/rmfakecloud:latest";
          name = "rmfakecloud";
          autoUpdate = "registry";
          environments = {
            STORAGE_URL = "http://192.168.1.2:${toString osConfig.ports.rmfakecloud}";
          };
          environmentFiles = [ osConfig.sops.secrets.rmfakecloud_env.path ];
          volumes = [
            "${RMCLOUD_CONTAINER_PATH}/data:/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.rmfakecloud}:3000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=rmfakecloud.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      paperless-ngx = {
        containerConfig = {
          image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
          name = "paperless-ngx";
          autoUpdate = "registry";
          environments = {
            PAPERLESS_REDIS = "redis://paperless-ngx-redis:6379";
            PAPERLESS_DBHOST = "paperless-ngx-postgres";
            USERMAP_UID = "1026";
            USERMAP_GID = "101";
            PAPERLESS_OCR_LANGUAGES = "eng";
            PAPERLESS_TIME_ZONE = osConfig.meta.timezone;
            PAPERLESS_OCR_LANGUAGE = "eng";
          };
          environmentFiles = [ osConfig.sops.secrets.paperless_env.path ];
          volumes = [
            "${PAPERLESS_CONTAINER_PATH}/data:/data"
            "${PAPERLESS_CONTAINER_PATH}/media:/media"
            "/kuckyjar/media/paperless/export:/usr/src/paperless/export"
            "/kuckyjar/media/paperless/consume:/usr/src/paperless/consume"
          ];
          publishPorts = [
            "${toString osConfig.ports.paperless}:8000"
          ];
          networks = [ networks.paperless.ref ];
          pod = pods.paperless.ref;
          labels = [
            "caddy.enable=true"
            "caddy.host=paperless.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [ containers.paperless-ngx-postgres.ref ];
          After = [ containers.paperless-ngx-redis.ref ];
        };
      };

      paperless-ngx-redis = {
        containerConfig = {
          image = "docker.io/library/redis:8";
          name = "paperless-ngx-redis";
          autoUpdate = "registry";
          volumes = [
            "${PAPERLESS_CONTAINER_PATH}/redisdata:/data"
          ];
          networks = [ networks.paperless.ref ];
          pod = pods.paperless.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      paperless-ngx-postgres = {
        containerConfig = {
          image = "docker.io/library/postgres:15";
          name = "paperless-ngx-postgres";
          autoUpdate = "registry";
          environmentFiles = [ osConfig.sops.secrets.paperless_postgres_env.path ];
          volumes = [
            "${PAPERLESS_CONTAINER_PATH}/pgdata:/var/lib/postgresql/data"
          ];
          networks = [ networks.paperless.ref ];
          pod = pods.paperless.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
