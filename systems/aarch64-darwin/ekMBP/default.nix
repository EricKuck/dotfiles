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
      ios.enable = true;
      rust.enable = true;
      backups.enable = true;
    };

    programs = {
      nh = {
        enable = true;
        flake = "path:/Users/eric/.config/nix";
        clean = {
          enable = true;
          extraArgs = "--keep-since 4d --keep 3";
        };
      };
    };
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/ekmbp.yaml";
    age.sshKeyPaths = [ "${config.users.users.eric.home}/.ssh/id_ed25519_sops" ];
    secrets = {
      btt_license = { };
      istat_menus_license = { };
    };
  };

  environment.systemPackages = with pkgs; [
    sops
    (lib.custom.scripts.activate-btt pkgs)
    (lib.custom.scripts.activate-istat pkgs)
  ];

  homebrew = {
    casks = [
      "orcaslicer"
      "winbox"
      "autodesk-fusion"
      "thunderbird"
      "signal"
      "inkscape"
      "vial"
    ];

    masApps = {
      Tailscale = 1475387142;
      WireGuard = 1451685025;
      Infuse = 1136220934;
      "MQTT Explorer" = 1455214828;
    };
  };

  system.stateVersion = 6;
}
