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
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.matchers.host=drop.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
