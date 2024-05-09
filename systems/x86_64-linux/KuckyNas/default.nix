{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "sd_mod"
      ];
      kernelModules = [ ];
    };

    kernelModules = [ "kvm-intel" ];
    kernelPackages = lib.mkDefault pkgs.zfs.latestCompatibleLinuxPackages;

    extraModulePackages = [ ];

    loader = {
      timeout = 0;
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    supportedFilesystems = [ "zfs" ];

    zfs = {
      extraPools = [
        "kuckyjar"
        "backups"
      ];
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

  swapDevices = [ ];

  security.wrappers = {
    kopia = {
      owner = "eric";
      group = "users";
      capabilities = "cap_dac_read_search=+ep";
      source = lib.getExe' pkgs.kopia "kopia";
    };
    kopia-backup-all = {
      owner = "eric";
      group = "users";
      capabilities = "cap_dac_read_search=+ep";
      source = lib.custom.scripts.kopia-backup pkgs;
    };
  };

  networking = {
    useDHCP = lib.mkDefault true;
    hostId = "219f142e";
    enableIPv6 = false;
    defaultGateway = "192.168.1.1";
    networkmanager.enable = true;
    nameservers = [ "192.168.1.1" ];
    firewall = {
      enable = false;
    };
  };

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    useXkbConfig = false;
  };

  users.users = {
    root = {
      hashedPassword = "!";
    };

    eric = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "podman"
      ];
      shell = pkgs.fish;
      linger = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE9qlhgSQ5US+fHi66PePPM5cdafOVNJ74Ok2wFS8bWF erickuck"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    cockpit
    custom.cockpit-podman
    wireguard-go
    eternal-terminal
    lm_sensors
    zfs
  ];

  programs = {
    fish.enable = true;
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    eternal-terminal.enable = true;

    cockpit = {
      enable = true;
      port = 5000;
      settings = {
        WebService = {
          AllowUnencrypted = true;
        };
      };
    };

    zfs = {
      autoScrub = {
        enable = true;
        interval = "Sun, 02:00";
        pools = [
          "kuckyjar"
          "backups"
        ];
      };

      trim = {
        enable = true;
        interval = "weekly";
      };

      autoSnapshot = {
        enable = true;
        flags = "-k -p --utc";
        frequent = lib.mkDefault 0;
        hourly = lib.mkDefault 0;
        daily = lib.mkDefault 3;
        weekly = lib.mkDefault 3;
        monthly = lib.mkDefault 0;
      };
    };
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
