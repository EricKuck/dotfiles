{
  libs,
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-3
  ];

  custom = {
    environments.server = {
      enable = true;
      quadlets.enable = true;
    };
  };

  meta.containerData = "${osConfig.meta.flake.ownerHome}/container";

  boot = {
    kernelPackages = pkgs.linuxKernel.packages.linux_rpi3;
    initrd.availableKernelModules = [
      "xhci_pci"
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
      "${config.meta.flake.owner}".openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "24.05"; # Did you read the comment?
  };
}
