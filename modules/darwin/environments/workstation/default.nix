{
  lib,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.workstation;
in
{
  options.custom.environments.workstation = {
    enable = mkEnableOption "workstation";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "bitwarden"
        "battery"
        "notesnook"
        "macmediakeyforwarder"
        {
          name = "intellij-idea@eap";
          greedy = true;
        }
        "visual-studio-code"
        "istat-menus"
        "mullvad-vpn"
        "figma"
        "slack"
        "element"
        "cameracontroller"
        "discord"
        "meetingbar"
        "grishka/grishka/neardrop"
        "macshot"
      ];

      masApps = {
        Gifski = 1351639930;
        Tailscale = 1475387142;
      };
    };
  };
}
