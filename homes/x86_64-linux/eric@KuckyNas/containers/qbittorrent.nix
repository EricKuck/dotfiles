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
            TORRENTING_PORT = "6881";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/downloads:/downloads"
            "${CONTAINER_PATH}/vuetorrent:/vuetorrent"
          ];
          publishPorts = [
            "9090:9090"
            "6881:6881"
            "6881:6881/udp"
          ];
          networks = [
            containers.wireguard.ref
          ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.upstream.port=9090"
            "com.caddyserver.http.matchers.host=qbittorrent.kuck.ing"
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
