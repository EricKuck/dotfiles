{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/multi-scrobbler";
in
{
  quadlets = {
    containers = {
      multi-scrobbler = {
        containerConfig = {
          image = "docker.io/foxxmd/multi-scrobbler";
          name = "multi-scrobbler";
          autoUpdate = "registry";
          environments = {
            BASE_URL = "https://scrobbler.kuck.ing";
          };
          environmentFiles = [ osConfig.sops.secrets.multi-scrobbler_env.path ];
          volumes = [
            "${CONTAINER_PATH}/config:/config"
          ];
          publishPorts = [
            "${toString osConfig.ports.multi-scrobbler}:9078"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=scrobbler.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
