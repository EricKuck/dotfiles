{ config, osConfig, ... }:
let
  HA_CONTAINER_PATH = "${osConfig.meta.containerData}/homeassistant";
  MUSIC_CONTAINER_PATH = "${osConfig.meta.containerData}/music-assistant";
in
{
  quadlets = {
    containers = {
      homeassistant = {
        containerConfig = {
          image = "docker.io/homeassistant/home-assistant:latest";
          name = "homeassistant";
          autoUpdate = "registry";
          networks = [ "host" ];
          volumes = [
            "${HA_CONTAINER_PATH}/config:/config"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.homeassistant}"
            "caddy.host=ha.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      music-assistant-server = {
        containerConfig = {
          image = "ghcr.io/music-assistant/server:latest";
          name = "music-assistant-server";
          autoUpdate = "registry";
          networks = [ "host" ];
          volumes = [
            "${MUSIC_CONTAINER_PATH}/data:/data"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.port=${toString osConfig.ports.music-assistant_web}"
            "caddy.host=music.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
