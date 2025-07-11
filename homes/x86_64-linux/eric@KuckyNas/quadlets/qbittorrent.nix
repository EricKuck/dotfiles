{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/qbittorrent";
  inherit (config.virtualisation.quadlet) containers networks;
in
{
  quadlets = {
    containers = {
      qbittorrent = {
        containerConfig = {
          image = "lscr.io/linuxserver/qbittorrent:latest";
          name = "qbittorrent";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
            UMASK = "022";
            WEBUI_PORT = "9090";
            TORRENTING_PORT = "6881";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/downloads:/downloads"
            "${CONTAINER_PATH}/vuetorrent:/vuetorrent"
          ];
          publishPorts = [
            "${toString osConfig.ports.qbittorrent}:9090"
            "${toString osConfig.ports.qbittorrent_torrent}:6881"
            "${toString osConfig.ports.qbittorrent_torrent}:6881/udp"
          ];
          networks = [
            containers.wireguard.ref
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.qbittorrent}"
            "caddy.host=qbittorrent.kuck.ing"
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
