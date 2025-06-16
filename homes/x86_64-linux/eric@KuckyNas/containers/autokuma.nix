{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/autokuma";
in
{
  virtualisation.quadlet = {
    containers = {
      autokuma = {
        containerConfig = {
          image = "ghcr.io/bigboot/autokuma:latest";
          name = "autokuma";
          autoUpdate = "registry";
          environments = {
            TZ = "America/New_York";
            AUTOKUMA__KUMA__URL = "http://localhost:3001";
            AUTOKUMA__TAG_NAME = "podman";
            AUTOKUMA__DOCKER__HOSTS = "unix:///var/run/podman.sock";
          };
          environmentFiles = [ osConfig.sops.secrets.autokuma_env.path ];
          networks = [ "host" ];
          volumes = [
            "${CONTAINER_PATH}/data:/data"
            "/kuckyjar/container/autokuma/autokuma.toml:/autokuma.toml"
            "/run/user/1000/podman/podman.sock:/var/run/podman.sock"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
