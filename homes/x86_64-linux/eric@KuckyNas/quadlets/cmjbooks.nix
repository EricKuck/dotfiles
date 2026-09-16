{ config, osConfig, ... }:
let
  BOOKS_PATH = "${osConfig.meta.containerData}/CMJ Books";
  HOST = "cmjbooks.kuck.ing";
  inherit (config.virtualisation.quadlet) builds;
in
{
  quadlets = {
    builds = {
      cmjbooks = {
        buildConfig = {
          tag = "localhost/cmjbooks:latest";
          file = "${BOOKS_PATH}/10_App/docker/Dockerfile";
          workdir = "${BOOKS_PATH}/10_App";
        };
      };
    };

    containers = {
      cmjbooks = {
        containerConfig = {
          image = builds.cmjbooks.ref;
          name = "cmjbooks";
          userns = "keep-id:uid=1000,gid=1000";
          environments = {
            CMJ_DAILY_AT = "06:00";
            CMJ_KEY_FILE = "/run/secrets/cmj-key";
          };
          volumes = [
            "${BOOKS_PATH}:/books"
            "${config.home.homeDirectory}/.claude:/home/cmj/.claude"
            "${osConfig.sops.secrets.cmjbooks_key.path}:/run/secrets/cmj-key:ro"
          ];
          publishPorts = [
            "127.0.0.1:${toString osConfig.ports.cmjbooks}:8765"
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
