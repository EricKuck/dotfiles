{ osConfig, ... }:
{
  quadlets = {
    containers = {
      bitwarden-mxroute-server = {
        containerConfig = {
          image = "ghcr.io/bfpimentel/bitwarden-mxroute-server:latest";
          name = "bitwarden-mxroute-server";
          autoUpdate = "registry";
          environmentFiles = [ osConfig.sops.secrets.bitwarden_mxroute_env.path ];
          publishPorts = [
            "${toString osConfig.ports.bitwarden_mxroute}:6123"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=bitwarden-mxroute.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
