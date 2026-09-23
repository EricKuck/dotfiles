{ config, osConfig, ... }:
let
  BOOKS_PATH = "${osConfig.meta.containerData}/IRL Books";
  HOST = "irlbooks.kuck.ing";
  inherit (config.virtualisation.quadlet) builds;
in
{
  quadlets = {
    builds = {
      irlbooks = {
        buildConfig = {
          tag = "localhost/irlbooks:latest";
          file = "${BOOKS_PATH}/10_App/docker/Dockerfile";
          workdir = "${BOOKS_PATH}/10_App";
        };
      };
    };

    containers = {
      irlbooks = {
        containerConfig = {
          image = builds.irlbooks.ref;
          name = "irlbooks";
          userns = "keep-id:uid=1000,gid=1000";
          environments = {
            IRL_DAILY_AT = "00:00";
            IRL_KEY_FILE = "/run/secrets/irl-key";
            RCLONE_CONFIG = "/books/10_App/data/rclone.conf";
          };
          volumes = [
            "${BOOKS_PATH}:/books"
            "${config.home.homeDirectory}/.claude:/home/irl/.claude"
            "${osConfig.sops.secrets.irlbooks_key.path}:/run/secrets/irl-key:ro"
          ];
          publishPorts = [
            "127.0.0.1:${toString osConfig.ports.irlbooks}:8765"
          ];
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
