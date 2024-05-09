{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:
{
  nix = {
    registry = (lib.mapAttrs (_: flake: { inherit flake; })) (
      (lib.filterAttrs (_: lib.isType "flake")) inputs
    );

    package = pkgs.nixUnstable;

    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = false;
    };

    gc = {
      automatic = true;
      interval = {
        Day = 7;
      };
      options = "--delete-older-than 30d";
      #      user = config.custom.user.name;
    };

    generateRegistryFromInputs = true;
    generateNixPathFromInputs = true;
    linkInputs = true;
    useDaemon = true;
  };
}
