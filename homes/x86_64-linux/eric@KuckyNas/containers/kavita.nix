{ config, osConfig, ... }:
let
  CONTAINER_PATH = "/kuckyjar/container/kavita";
in
{
  virtualisation.quadlet = {
    containers = {
      kavita = {
        containerConfig = {
          image = "docker.io/jvmilazz0/kavita:latest";
          name = "kavita";
          autoUpdate = "registry";
          environments = {
            TZ = "America/New_York";
          };
          volumes = [
            "${CONTAINER_PATH}:/kavita/config"
            "/kuckyjar/media/Manga:/manga"
            "/kuckyjar/media/Comics:/comics"
          ];
          publishPorts = [
            "${toString osConfig.ports.kavita}:5000/tcp"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=kavita.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
