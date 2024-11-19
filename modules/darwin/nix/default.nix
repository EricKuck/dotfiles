{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:
{
  services.nix-daemon.enable = true;

  nix = {
    registry = (lib.mapAttrs (_: flake: { inherit flake; })) (
      (lib.filterAttrs (_: lib.isType "flake")) inputs
    );

    package = pkgs.nixVersions.latest;

    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = false;
    };

    generateRegistryFromInputs = true;
    generateNixPathFromInputs = true;
    linkInputs = true;
    useDaemon = true;
  };
}
