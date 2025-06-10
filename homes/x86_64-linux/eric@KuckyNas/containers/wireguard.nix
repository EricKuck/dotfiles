{ config, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/wireguard";
  inherit (config.virtualisation.quadlet) networks;
in
{
  virtualisation.quadlet = {
    networks.wireguard.networkConfig.driver = "bridge";

    containers = {
      wireguard = {
        containerConfig = {
          image = "lscr.io/linuxserver/wireguard";
          name = "wireguard";
          autoUpdate = "registry";
          environments = {
            PUID = "1048";
            PGID = "1048";
            TZ = "America/New_York";
          };
          volumes = [
            "${CONTAINER_PATH}/config:/config"
            "${CONTAINER_PATH}/init:/custom-cont-init.d:ro"
          ];
          publishPorts = [
            "51820:51820/udp"
            "9090:9090"
            "9117:9117"
            "8137:8137"
          ];
          networks = [ networks.wireguard.ref ];
          addCapabilities = [ "NET_ADMIN" ];
          sysctl = {
            "net.ipv4.conf.all.src_valid_mark" = "1";
          };
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
