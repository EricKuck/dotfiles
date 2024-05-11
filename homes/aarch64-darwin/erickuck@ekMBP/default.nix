{
  inputs,
  lib,
  pkgs,
  config,
  osConfig ? { },
  ...
}:
with lib.custom;
{
  custom = {
    cli-apps = {
      common.enable = true;
    };
  };

  home = {
    sessionVariables = {
      JAVA_HOME = "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home";
    };

    sessionPath = [
      "${osConfig.users.users.erickuck.home}/Library/Android/sdk/platform-tools"
      "${osConfig.users.users.erickuck.home}/Library/Android/sdk/tools"
    ];

    packages = with pkgs; [
      cloc
      eternal-terminal
      tailscale
      scrcpy
    ];

    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
