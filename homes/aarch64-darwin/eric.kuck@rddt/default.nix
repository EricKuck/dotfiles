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
      zellij.enable = true;
    };

    environments = {
      android.enable = true;
      ios.enable = true;
      golang.enable = true;
      rust.enable = true;
    };
  };

  home = {
    packages = with pkgs; [
      cloc
      eternal-terminal
      scrcpy
    ];

    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
