{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/syncthing";
in
{
  virtualisation.quadlet = {
    containers = {
      syncthing = {
        containerConfig = {
          image = "lscr.io/linuxserver/syncthing:latest";
          name = "syncthing";
          autoUpdate = "registry";
          environments = {
            PGID = "1008";
            PUID = "1008";
            TZ = "America/New_York";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/data:/data"
          ];
          publishPorts = [
            "21027:21027/udp"
            "22000:22000/tcp"
            "22000:22000/udp"
            "8384:8384/tcp"
          ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.upstream.port=8384"
            "com.caddyserver.http.matchers.host=syncthing.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
