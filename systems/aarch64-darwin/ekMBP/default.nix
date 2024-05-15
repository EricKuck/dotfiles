{
  lib,
  pkgs,
  config,
  ...
}:
with lib.custom;
{
  custom = {
    environments = {
      common.enable = true;
      android.enable = true;
      backups.enable = true;
    };
  };

  homebrew = {
    casks = [
      "orcaslicer"
      "nrlquaker-winbox"
    ];
  };

  system.stateVersion = 4;
}
