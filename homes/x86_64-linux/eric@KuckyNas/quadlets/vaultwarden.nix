{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/vaultwarden";
  HOST = "pass.kuck.ing";
in
{
  quadlets = {
    containers = {
      vaultwarden = {
        containerConfig = {
          image = "docker.io/vaultwarden/server:latest";
          name = "vaultwarden";
          autoUpdate = "registry";
          environments = {
            DOMAIN = "https://${HOST}";
            PUSH_ENABLED = "true";
            SMTP_HOST = "mail.smtp2go.com";
            INVITATIONS_ALLOWED = "false";
            SIGNUPS_ALLOWED = "false";
            SHOW_PASSWORD_HINT = "false";
            ROCKET_PORT = "8080";
          };
          environmentFiles = [ osConfig.sops.secrets.vaultwarden_env.path ];
          volumes = [
            "${CONTAINER_PATH}/data:/data"
          ];
          publishPorts = [
            "${toString osConfig.ports.vaultwarden}:8080"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=${HOST}"
          ];
          user = osConfig.serviceOwners.vaultwarden;
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
