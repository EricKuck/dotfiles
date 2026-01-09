{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  custom = {
    environments.server = {
      enable = true;
      quadlets.enable = true;
    };
  };

  meta = {
    ipAddress = "192.168.1.3";
    containerData = "/home/${config.meta.flake.owner}/container";
    containerCache = "/home/${config.meta.flake.owner}/container-cache";
  };

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
        "sr_mod"
      ];
      kernelModules = [ ];
      systemd.enable = true;
    };

    kernelModules = [ "kvm-intel" ];
    kernelPackages = pkgs.linuxPackages_6_18;
    kernel.sysctl = {
      "vm.swappiness" = 30;
      "vm.vfs_cache_pressure" = 50;
    };
    extraModulePackages = [ ];

    loader = {
      timeout = 0;
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXROOT";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024;
    }
  ];

  networking = {
    hostId = "32981d0e";
    useDHCP = false;
    interfaces.enp3s0.ipv4.addresses = [
      {
        address = config.meta.ipAddress;
        prefixLength = 24;
      }
    ];
  };

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;

  users = {
    users = {
      "${config.meta.flake.owner}" = {
        openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];
        extraGroups = [ "dialout" ];
      };
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
