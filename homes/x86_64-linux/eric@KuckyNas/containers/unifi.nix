{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/unifi";
in
{
  virtualisation.quadlet = {
    containers = {
      unifi = {
        containerConfig = {
          image = "docker.io/jacobalberty/unifi";
          name = "unifi";
          autoUpdate = "registry";
          environments = {
            TZ = "America/New_York";
          };
          volumes = [
            "${CONTAINER_PATH}:/unifi"
          ];
          publishPorts = [
            "8080:8080"
            "8443:8443"
            "3478:3478/udp"
          ];
          user = "999:999";
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
