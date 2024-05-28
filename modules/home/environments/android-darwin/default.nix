{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.android-darwin;

  android_home = "/Users/${config.snowfallorg.user.name}/Library/Android/sdk";
  java_home =
    version:
    "${pkgs."zulu${builtins.toString version}"}/zulu-${builtins.toString version}.jdk/Contents/Home";
  set_java_home = version: "set -x JAVA_HOME ${java_home version}";
in
{
  options.custom.environments.android-darwin = {
    enable = mkEnableOption "android-darwin";
  };

  config = mkIf cfg.enable {
    home = {
      shellAliases = {
        java11 = set_java_home 11;
        java17 = set_java_home 17;
        java21 = set_java_home 21;
      };

      sessionVariables = {
        ANDROID_HOME = android_home;
      };

      sessionPath = [
        "${android_home}/platform-tools"
        "${android_home}/tools"
      ];

      #symlinks to make finding these through finder easier (ex: for IntelliJ)
      file = {
        "jdk/zulu11.jdk".source = java_home 11;
        "jdk/zulu17.jdk".source = java_home 17;
        "jdk/zulu21.jdk".source = java_home 21;
      };
    };

    programs.fish.interactiveShellInit = set_java_home 17;
  };
}
