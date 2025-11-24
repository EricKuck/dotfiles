{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
with lib.custom;
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  custom = {
    environments = {
      common.enable = true;
      android.enable = true;
      rust.enable = true;
      backups.enable = true;
    };

    programs = {
      nh.enable = true;
    };
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/ekmbp.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
    secrets = {
      btt_license = { };
      istat_menus_license = { };
      mqtt_creds.owner = config.meta.flake.owner;
    };
  };

  environment.systemPackages = with pkgs; [
    sops
  ];

  homebrew = {
    casks = [
      "bambu-studio"
      "winbox"
      "autodesk-fusion"
      "openscad@snapshot"
      "mailspring"
      "signal"
      "inkscape"
      "vial"
      "utm"
    ];

    masApps = {
      Tailscale = 1475387142;
      WireGuard = 1451685025;
      Infuse = 1136220934;
      "MQTT Explorer" = 1455214828;
      PagerCall = 6740581987;
    };
  };

  system.stateVersion = 6;
}
