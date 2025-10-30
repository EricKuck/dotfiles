{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/immich";
  CONTAINER_CACHE_PATH = "${osConfig.meta.containerCache}/immich";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  quadlets = {
    networks.immich.networkConfig.driver = "bridge";

    pods.immich = { };

    containers = {
      immich-server = {
        containerConfig = {
          image = "ghcr.io/immich-app/immich-server:release";
          autoUpdate = "registry";
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
          image = "ghcr.io/immich-app/immich-machine-learning:release";
          autoUpdate = "registry";
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
          image = "docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa";
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
          image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:41eacbe83eca995561fe43814fd4891e16e39632806253848efaf04d3c8a8b84";
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
