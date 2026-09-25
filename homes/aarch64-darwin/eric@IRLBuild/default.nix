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
  };

  home = {
    packages = with pkgs; [
      cloc
      eternal-terminal
    ];

    # NEVER change this value after the initial install, for any reason,
    stateVersion = "26.05"; # Did you read the comment?
  };
}
