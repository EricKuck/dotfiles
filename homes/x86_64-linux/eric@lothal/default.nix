{
  lib,
  pkgs,
  inputs,
  config,
  osConfig ? { },
  ...
}:
with lib.custom;
{
  imports = [
    ./quadlets
  ];

  custom = {
    environments.server = {
      enable = true;
      podman.enable = true;
    };
  };
}
