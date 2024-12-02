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
      ios.enable = true;
      rust.enable = true;
    };

    programs = {
      nh = {
        enable = true;
        flake = "path:/Users/eric/.config/nix";
        hostname = "rddt";
        clean = {
          enable = true;
          extraArgs = "--keep-since 4d --keep 3";
        };
      };
    };
  };

  system.stateVersion = 4;
}
