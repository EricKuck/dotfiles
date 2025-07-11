{ config, osConfig, ... }:
let
  CONTAINER_PATH = "${osConfig.meta.containerData}/kavita";
in
{
  quadlets = {
    containers = {
      kavita = {
        containerConfig = {
          image = "docker.io/jvmilazz0/kavita:latest";
          name = "kavita";
          autoUpdate = "registry";
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
