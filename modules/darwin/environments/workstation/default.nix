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
        "istat-menus"
        "mullvad-vpn"
        "figma"
        "slack"
        "element"
        "cameracontroller"
        "discord"
        "macshot"
      ];

      masApps = {
        Gifski = 1351639930;
        Tailscale = 1475387142;
      };
    };
  };
}
