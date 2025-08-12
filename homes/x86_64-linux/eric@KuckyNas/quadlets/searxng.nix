{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/searxng";
  SEAR_CACHE_PATH = "${osConfig.meta.containerCache}/searxng";
  REDIS_CACHE_PATH = "${osConfig.meta.containerCache}/searxng-redis";
  HOST = "search.kuck.ing";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  quadlets = {
    networks.searxng.networkConfig.driver = "bridge";

    pods.searxng = { };

    containers = {
      searxng-redis = {
        containerConfig = {
          image = "docker.io/valkey/valkey:8-alpine";
          name = "searxng-redis";
          autoUpdate = "registry";
          volumes = [
            "${REDIS_CACHE_PATH}:/data"
          ];
          exec = "valkey-server --save 30 1 --loglevel warning";
          networks = [ networks.searxng.ref ];
          pod = pods.searxng.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      searxng-search = {
        containerConfig = {
          image = "docker.io/searxng/searxng:latest";
          name = "searxng-search";
          autoUpdate = "registry";
          environments = {
            SEARXNG_BASE_URL = "https://${HOST}/";
          };
          volumes = [
            "${CONTAINER_PATH}:/etc/searxng"
            "${SEAR_CACHE_PATH}:/cache"
          ];
          publishPorts = [
            "${toString osConfig.ports.searxng}:8080"
          ];
          networks = [ networks.searxng.ref ];
          pod = pods.searxng.ref;
          labels = [
            "caddy.enable=true"
            "caddy.host=${HOST}"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
