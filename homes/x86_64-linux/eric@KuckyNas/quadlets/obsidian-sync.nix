{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/obsidian-sync";
in
{
  quadlets = {
    containers = {
      obsidian-sync = {
        containerConfig = {
          image = "docker.io/couchdb:latest";
          name = "obsidian-sync";
          autoUpdate = "registry";
          environments = {
            COUCHDB_USER = "obsidian";
          };
          environmentFiles = [
            osConfig.sops.secrets.obsidian-sync_env.path
          ];
          volumes = [
            "${CONTAINER_PATH}/data:/opt/couchdb/data"
            "${CONTAINER_PATH}/etc:/opt/couchdb/etc/local.d"
          ];
          publishPorts = [
            "${toString osConfig.ports.obsidian-sync}:5984"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=obsidian.kuck.ing"
          ];

          user = "3793:3793";
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
