{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/qbittorrent";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  virtualisation.quadlet = {
    containers = {
      qbittorrent = {
        containerConfig = {
          image = "lscr.io/linuxserver/qbittorrent:latest";
          name = "qbittorrent";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            TZ = "America/New_York";
            UMASK = "022";
            WEBUI_PORT = "9090";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/downloads:/downloads"
            "${CONTAINER_PATH}/vuetorrent:/vuetorrent"
          ];
          publishPorts = [
            "1883:1883"
            "9001:9001"
          ];
          networks = [
            containers.wireguard.ref
          ];
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
