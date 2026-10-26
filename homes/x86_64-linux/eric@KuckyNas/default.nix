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

  # registry credentials for private images (e.g. ghcr.io/erickuck/oura)
  xdg.configFile."containers/auth.json".source =
    config.lib.file.mkOutOfStoreSymlink
      osConfig.sops.templates."containers-auth.json".path;

  home.packages = with pkgs; [
    ffmpeg
    sacad
  ];
}
