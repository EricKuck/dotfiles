{ osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/oura";
in
{
  quadlets = {
    containers = {
      oura = {
        containerConfig = {
          image = "ghcr.io/erickuck/oura:latest";
          name = "oura";
          autoUpdate = "registry";
          environments = {
            OURA_API_TOKEN = "eee";
            OURA_TZ_OFFSET = "-4";
            OURA_SCORE_PARAMS = "/models/score_params.json";
          };
          volumes = [
            "${CONTAINER_PATH}/data:/data"
            "${CONTAINER_PATH}/models:/models"
          ];

          publishPorts = [
            "${toString osConfig.ports.oura}:8099"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=oura.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
