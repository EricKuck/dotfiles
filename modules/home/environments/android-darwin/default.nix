{ lib, config, ... }:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.android-darwin;
in
{
  options.custom.environments.android-darwin = {
    enable = mkEnableOption "android-darwin";
  };

  config = mkIf cfg.enable {
    home = {
      sessionVariables = {
        JAVA_HOME = "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home";
        ANDROID_HOME = "/Users/${config.snowfallorg.user.name}/Library/Android/sdk";
      };

      sessionPath = [
        "/Users/${config.snowfallorg.user.name}/Library/Android/sdk/platform-tools"
        "/Users/${config.snowfallorg.user.name}/Library/Android/sdk/tools"
      ];
    };
  };
}
