{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/pairdrop";
in
{
  quadlets = {
    containers = {
      pairdrop = {
        containerConfig = {
          image = "lscr.io/linuxserver/pairdrop:latest";
          name = "pairdrop";
          autoUpdate = "registry";
          publishPorts = [
            "${toString osConfig.ports.pairdrop}:3000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=drop.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
