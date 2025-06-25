{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/karakeep";
  inherit (config.virtualisation.quadlet) containers networks pods;
in
{
  virtualisation.quadlet = {
    networks.karakeep.networkConfig.driver = "bridge";

    pods.karakeep = { };

    containers = {
      karakeep-web = {
        containerConfig = {
          image = "ghcr.io/karakeep-app/karakeep:release";
          name = "karakeep-web";
          autoUpdate = "registry";
          environments = {
            MEILI_ADDR = "http://karakeep-meilisearch:7700";
            BROWSER_WEB_URL = "http://karakeep-chrome:9222";
            DATA_DIR = "/data";
          };
          environmentFiles = [ osConfig.sops.secrets.karakeep_env.path ];
          volumes = [
            "${CONTAINER_PATH}/data:/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.karakeep}:3000"
          ];
          networks = [ networks.karakeep.ref ];
          pod = pods.karakeep.ref;
          labels = [
            "caddy.enable=true"
            "caddy.host=karakeep.kuck.ing"
            "caddy.enable=true"
            "caddy.host=karakeep.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      karakeep-chrome = {
        containerConfig = {
          image = "gcr.io/zenika-hub/alpine-chrome:latest";
          name = "karakeep-chrome";
          autoUpdate = "registry";
          exec = [
            "--no-sandbox"
            "--disable-gpu"
            "--disable-dev-shm-usage"
            "--remote-debugging-address=0.0.0.0"
            "--remote-debugging-port=9222"
            "--hide-scrollbars"
          ];
          networks = [ networks.karakeep.ref ];
          pod = pods.karakeep.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      karakeep-meilisearch = {
        containerConfig = {
          image = "getmeili/meilisearch:v1.13.3";
          name = "karakeep-meilisearch";
          environmentFiles = [ osConfig.sops.secrets.karakeep_env.path ];
          volumes = [
            "${CONTAINER_PATH}/meilisearch:/meili_data"
          ];
          networks = [ networks.karakeep.ref ];
          pod = pods.karakeep.ref;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
