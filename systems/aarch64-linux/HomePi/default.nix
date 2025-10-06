{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  custom = {
    environments.server = {
      enable = true;
      quadlets.enable = true;
    };
  };

  meta = {
    ipAddress = "192.168.1.3";
    containerData = "${config.meta.flake.ownerHome}/container";
  };

  boot = {
    initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
    ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  hardware.enableRedistributableFirmware = true;

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/homepi.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
  };

  users = {
    users = {
      "${config.meta.flake.owner}" = {
        openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];
        extraGroups = [
          "dialout"
        ];
      };
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "24.05"; # Did you read the comment?
  };
}
