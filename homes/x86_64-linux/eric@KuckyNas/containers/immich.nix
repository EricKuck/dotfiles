{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/immich";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  virtualisation.quadlet = {
    networks.immich.networkConfig.driver = "bridge";

    pods.immich = { };

    containers = {
      immich-server = {
        containerConfig = {
          image = "ghcr.io/immich-app/immich-server:release";
          name = "immich_server";
          environmentFiles = [ osConfig.sops.secrets.immich_server_env.path ];
          volumes = [
            "${CONTAINER_PATH}/upload:/usr/src/app/upload"
            "/etc/localtime:/etc/localtime:ro"
          ];
          publishPorts = [
            "2283:2283"
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
          name = "immich_machine_learning";
          environmentFiles = [ osConfig.sops.secrets.immich_server_env.path ];
          volumes = [
            "${CONTAINER_PATH}/cache:/cache"
          ];
          publishPorts = [
            "2284:3003"
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
          image = "docker.io/valkey/valkey:8-bookworm@sha256:ff21bc0f8194dc9c105b769aeabf9585fea6a8ed649c0781caeac5cb3c247884";
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
          image = "ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0@sha256:fa4f6e0971f454cd95fec5a9aaed2ed93d8f46725cc6bc61e0698e97dba96da1";
          name = "immich_postgres";
          environments = {
            POSTGRES_INITDB_ARGS = "--data-checksums";
          };
          environmentFiles = [ osConfig.sops.secrets.immich_db_env.path ];
          volumes = [
            "${CONTAINER_PATH}/pgdata:/var/lib/postgresql/data"
          ];
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
