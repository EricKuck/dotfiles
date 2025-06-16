{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/scrypted";
in
{
  virtualisation.quadlet = {
    containers = {
      scrypted = {
        containerConfig = {
          image = "docker.io/koush/scrypted:latest";
          name = "scrypted";
          autoUpdate = "registry";
          networks = [ "host" ];
          volumes = [
            "${CONTAINER_PATH}/volume:/server/volume"
          ];
          labels = [
            "kuma.unifi.http.name=Scrypted"
            "kuma.unifi.http.url=https://scrypted.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
