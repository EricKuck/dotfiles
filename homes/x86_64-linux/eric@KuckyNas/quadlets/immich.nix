{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/immich";
  CONTAINER_CACHE_PATH = "${osConfig.meta.containerCache}/immich";
  IMMICH_VERSION = "v1.143.1";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  quadlets = {
    networks.immich.networkConfig.driver = "bridge";

    pods.immich = { };

    containers = {
      immich-server = {
        containerConfig = {
          image = "ghcr.io/immich-app/immich-server:${IMMICH_VERSION}";
          name = "immich_server";
          environmentFiles = [ osConfig.sops.secrets.immich_server_env.path ];
          volumes = [
            "${CONTAINER_PATH}/upload:/usr/src/app/upload"
            "/etc/localtime:/etc/localtime:ro"
          ];
          publishPorts = [
            "${toString osConfig.ports.immich}:2283"
          ];
          devices = [ "/dev/dri:/dev/dri" ];
          networks = [ networks.immich.ref ];
          pod = pods.immich.ref;
          labels = [
            "caddy.enable=true"
            "caddy.host=immich.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [
            containers.immich-redis.ref
            containers.immich-database.ref
          ];
          After = [
            containers.immich-redis.ref
            containers.immich-database.ref
          ];
        };
      };

      immich-machine-learning = {
        containerConfig = {
          image = "ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION}";
          name = "immich_machine_learning";
          environmentFiles = [ osConfig.sops.secrets.immich_server_env.path ];
          volumes = [
            "${CONTAINER_CACHE_PATH}/ml:/cache"
          ];
          publishPorts = [
            "${toString osConfig.ports.immich-ml}:3003"
          ];
          networks = [ networks.immich.ref ];
          pod = pods.immich.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      immich-redis = {
        containerConfig = {
          image = "docker.io/valkey/valkey:8-bookworm@sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571";
          name = "immich_redis";
          healthCmd = "redis-cli ping || exit 1";
          networks = [ networks.immich.ref ];
          pod = pods.immich.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      immich-database = {
        containerConfig = {
          image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:c44be5f2871c59362966d71eab4268170eb6f5653c0e6170184e72b38ffdf107";
          name = "immich_postgres";
          environments = {
            POSTGRES_INITDB_ARGS = "--data-checksums";
          };
          environmentFiles = [ osConfig.sops.secrets.immich_db_env.path ];
          volumes = [
            "${CONTAINER_PATH}/pgdata:/var/lib/postgresql/data"
          ];
          shmSize = "128mb";
          networks = [ networks.immich.ref ];
          pod = pods.immich.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
