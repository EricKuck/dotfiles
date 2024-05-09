{ lib, inputs, ... }:
{
  nix = {
    registry = (lib.mapAttrs (_: flake: { inherit flake; })) (
      (lib.filterAttrs (_: lib.isType "flake")) inputs
    );

    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
    };
  };
}
