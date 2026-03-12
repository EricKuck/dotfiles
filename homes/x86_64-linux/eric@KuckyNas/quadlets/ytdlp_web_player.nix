{ osConfig, ... }:
{
  quadlets = {
    containers = {
      ytdlp_web_player = {
        containerConfig = {
          image = "docker.io/matszwe02/ytdlp_web_player:latest";
          name = "ytdlp_web_player";
          autoUpdate = "registry";
          environments = {
            APP_TITLE = "YT-DLP Player";
            THEME_COLOR = "#ff7300";
            GENERATE_SPRITE_BELOW = "1800";
            AMOLED_BG = "false";
            MAX_VIDEO_AGE = "3600";
            MAX_VIDEO_DURATION = "36000";
            DEFAULT_QUALITY = "720";
            LOAD_DEFAULT_QUALITY = "true";
          };
          publishPorts = [
            "${toString osConfig.ports.ytdlp_web_player}:5000"
          ];
          labels = [
            "caddy.enable=true"
            "caddy.host=ytdlp.kuck.ing"
          ];
        };
        serviceConfig = {
          Restart = "always";
        };
      };
    };
  };
}
