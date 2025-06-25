{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/pairdrop";
in
{
  virtualisation.quadlet = {
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
