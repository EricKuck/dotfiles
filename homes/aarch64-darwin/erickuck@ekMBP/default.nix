{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
with lib.custom;
{
  custom = {
    cli-apps = {
      common.enable = true;
    };

    environments = {
      android-darwin.enable = true;
    };
  };

  home = {
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
