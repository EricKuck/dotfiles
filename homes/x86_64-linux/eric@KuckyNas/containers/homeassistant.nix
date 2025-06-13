{ config, ... }:
let
  HA_CONTAINER_PATH = "/kuckyjar/container/homeassistant";
  MUSIC_CONTAINER_PATH = "/kuckyjar/container/music-assistant";
  PIPER_CONTAINER_PATH = "/kuckyjar/container/wyoming-piper";
  WHISPER_CONTAINER_PATH = "/kuckyjar/container/wyoming-whisper";
  WAKEWORD_CONTAINER_PATH = "/kuckyjar/container/wyoming-openwakeword";
in
{
  virtualisation.quadlet = {
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
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.upstream.port=8123"
            "com.caddyserver.http.matchers.host=ha.kuck.ing"
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
          environments = {
            PUID = "1240";
            PGID = "1240";
            TZ = "America/New_York";
          };
          volumes = [
            "${MUSIC_CONTAINER_PATH}/data:/data"
          ];
          labels = [
            "com.caddyserver.http.enable=true"
            "com.caddyserver.http.upstream.port=8095"
            "com.caddyserver.http.matchers.host=music.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      wyoming-piper = {
        containerConfig = {
          image = "docker.io/rhasspy/wyoming-piper:latest";
          name = "wyoming-piper";
          autoUpdate = "registry";
          publishPorts = [
            "10200:10200"
          ];
          volumes = [
            "${PIPER_CONTAINER_PATH}/data:/data"
          ];
          exec = "--voice en_GB-northern_english_male-medium";
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      wyoming-whisper = {
        containerConfig = {
          image = "docker.io/rhasspy/wyoming-whisper:latest";
          name = "wyoming-whisper";
          autoUpdate = "registry";
          publishPorts = [
            "10300:10300"
          ];
          volumes = [
            "${WHISPER_CONTAINER_PATH}/data:/data"
          ];
          exec = "--model base --language en";
        };
        serviceConfig = {
          Restart = "always";
        };
      };

      wyoming-openwakeword = {
        containerConfig = {
          image = "docker.io/rhasspy/wyoming-openwakeword:latest";
          name = "wyoming-openwakeword";
          autoUpdate = "registry";
          publishPorts = [
            "10400:10400"
          ];
          volumes = [
            "${WAKEWORD_CONTAINER_PATH}/data:/data"
            "${WAKEWORD_CONTAINER_PATH}/config:/config"
            "${WAKEWORD_CONTAINER_PATH}/custom:/custom"
          ];
          exec = "--preload-model 'ok_nabu' --custom-model-dir /custom";
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
