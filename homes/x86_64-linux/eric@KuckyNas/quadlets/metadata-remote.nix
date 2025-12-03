{ config, osConfig, ... }:
{
  quadlets = {
    containers = {
      metadata-remote = {
        containerConfig = {
          image = "ghcr.io/wow-signal-dev/metadata-remote:latest";
          name = "metadata-remote";
          autoUpdate = "registry";
          environments = {
            PUID = "1072";
            PGID = "1072";
          };
          volumes = [
            "/kuckyjar/media/Music:/music"
          ];
          publishPorts = [
            "${toString osConfig.ports.metadata-remote}:8338"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=metadata-remote.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
