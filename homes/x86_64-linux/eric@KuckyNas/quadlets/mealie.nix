{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/mealie";
in
{
  quadlets = {
    containers = {
      mealie = {
        containerConfig = {
          image = "ghcr.io/mealie-recipes/mealie:latest";
          name = "mealie";
          autoUpdate = "registry";
          environments = {
            HOST = "0.0.0.0";
            WEB_CONCURRENCY = "1";
            BASE_URL = "http://${osConfig.meta.ipAddress}";
            ALLOW_SIGNUP = "true";
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
          user = osConfig.serviceOwners.mealie;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
