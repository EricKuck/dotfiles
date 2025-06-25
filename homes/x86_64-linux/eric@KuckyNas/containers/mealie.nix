{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/mealie";
in
{
  virtualisation.quadlet = {
    containers = {
      mealie = {
        containerConfig = {
          image = "ghcr.io/mealie-recipes/mealie:latest";
          name = "mealie";
          autoUpdate = "registry";
          environments = {
            HOST = "0.0.0.0";
            WEB_CONCURRENCY = "1";
            BASE_URL = "http://192.168.1.2";
            ALLOW_SIGNUP = "true";
            PUID = "1076";
            PGID = "1076";
            TZ = "America/New_York";
            MAX_WORKERS = "1";
          };
          volumes = [
            "${CONTAINER_PATH}/data:/app/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.mealie}:9000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=mealie.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
