{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:
{
  nix = {
    enable = true;

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
  };
}
