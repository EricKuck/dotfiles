{
  lib,
  config,
  pkgs,
  format,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.android;

  android_home =
    if format == "darwin" then
      "/Users/${config.snowfallorg.user.name}/Library/Android/sdk"
    else
      "${config.snowfallorg.user.home}/Android/Sdk";
  jdk_dir =
    version: "${pkgs."zulu${builtins.toString version}"}/zulu-${builtins.toString version}.jdk";
  java_home = version: "${jdk_dir version}/Contents/Home";
  set_java_home = version: "set -x JAVA_HOME ${java_home version}";
in
{
  options.custom.environments.android = {
    enable = mkEnableOption "android";
  };

  config = mkIf cfg.enable {
    home = {
      shellAliases = {
        java11 = set_java_home 11;
        java17 = set_java_home 17;
        java23 = set_java_home 23;
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
        "jdk/zulu23.jdk".source = java_home 23;
      };

      activation = {
        link_jvm = "/usr/bin/sudo ln -s ${jdk_dir 23} /Library/Java/JavaVirtualMachines/";
      };
    };

    programs.fish.interactiveShellInit = set_java_home 23;
  };
}
