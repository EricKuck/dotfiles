{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/unifi";
in
{
  quadlets = {
    containers = {
      unifi = {
        containerConfig = {
          image = "docker.io/jacobalberty/unifi";
          name = "unifi";
          autoUpdate = "registry";
          volumes = [
            "${CONTAINER_PATH}:/unifi"
          ];
          publishPorts = [
            "${toString osConfig.ports.unifi_stun}:3478/udp"
            "${toString osConfig.ports.unifi_comm}:8080"
            "${toString osConfig.ports.unifi}:8443"
          ];
          user = osConfig.serviceOwners.unifi;
          labels = [
            "caddy.port=${toString osConfig.ports.unifi}"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
