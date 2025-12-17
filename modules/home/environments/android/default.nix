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

  androidHome =
    if format == "darwin" then
      "/Users/${config.snowfallorg.user.name}/Library/Android/sdk"
    else
      "${config.snowfallorg.user.home}/Android/Sdk";
  jdkDir =
    version:
    "${pkgs."zulu${toString version}"}/Library/Java/JavaVirtualMachines/zulu-${toString version}.jdk";
  javaHome = version: "${jdkDir version}/Contents/Home";
  setJavaHome = version: "set -x JAVA_HOME ${javaHome version}";
in
{
  options.custom.environments.android = {
    enable = mkEnableOption "android";
  };

  config = mkIf cfg.enable {
    home = {
      shellAliases = {
        java11 = setJavaHome 11;
        java17 = setJavaHome 17;
        java25 = setJavaHome 25;
      };

      sessionVariables = {
        ANDROID_HOME = androidHome;
      };

      sessionPath = [
        "${androidHome}/platform-tools"
        "${androidHome}/tools"
      ];

      #symlinks to make finding these through finder easier (ex: for IntelliJ)
      file = {
        "jdk/zulu11.jdk".source = javaHome 11;
        "jdk/zulu17.jdk".source = javaHome 17;
        "jdk/zulu25.jdk".source = javaHome 25;
      };

      activation = {
        linkJvm = "/usr/bin/sudo ln -sfn ${jdkDir 25} /Library/Java/JavaVirtualMachines/";
      };
    };

    programs.fish.interactiveShellInit = setJavaHome 25;
  };
}
