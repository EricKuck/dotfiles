{ config, ... }:
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
            "3002:3000"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
