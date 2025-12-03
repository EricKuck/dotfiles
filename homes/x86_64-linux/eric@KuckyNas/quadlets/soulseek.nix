{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/soulseek";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  quadlets = {
    containers = {
      soulseek = {
        containerConfig = {
          image = "docker.io/slskd/slskd:latest";
          name = "soulseek";
          autoUpdate = "registry";
          environments = {
            SLSKD_REMOTE_CONFIGURATION = "true";
          };
          volumes = [
            "${CONTAINER_PATH}:/app"
          ];
          publishPorts = [
            "${toString osConfig.ports.soulseek_web}:5030"
            "${toString osConfig.ports.soulseek_dl}:50300"
          ];
          networks = [
            containers.wireguard.ref
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.soulseek_web}"
            "caddy.host=soulseek.kuck.ing"
          ];
          user = osConfig.serviceOwners.arr;
        };
        serviceConfig = {
          Restart = "always";
        };
        unitConfig = {
          Requires = [ containers.wireguard.ref ];
          After = [ containers.wireguard.ref ];
        };
      };
    };
  };
}
