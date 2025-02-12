{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:
with lib.custom;
{
  disabledModules = [ "services/monitoring/ups.nix" ];
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/monitoring/ups.nix"
    inputs.sops-nix.nixosModules.sops
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  custom = {
    programs = {
      nh = {
        enable = true;
        flake = "path:/home/eric/.config/nixos";
        hostname = config.system.name;
        clean = {
          enable = true;
          extraArgs = "--keep-since 4d --keep 3";
        };
      };
    };
  };

  hardware.coral.pcie.enable = true;

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
    # Pinning to 6.10, using the 6_11 definition as the 6_10 was removed because of being EOL
    kernelPackages = pkgs.linuxPackagesFor (
      pkgs.linuxKernel.kernels.linux_6_11.override {
        argsOverride = rec {
          src = pkgs.fetchurl {
            url = "mirror://kernel/linux/kernel/v${lib.versions.major version}.x/linux-${version}.tar.xz";
            sha256 = "sha256-VeW8vGjWZ3b8RolikfCiSES+tXgXNFqFTWXj0FX6Qj4=";
          };
          version = "6.10.14";
          modDirVersion = "6.10.14";
        };
      }
    );

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
      owner = config.users.users.eric.name;
      group = config.users.users.eric.group;
      capabilities = "cap_dac_read_search=+ep";
      source = lib.getExe' pkgs.kopia "kopia";
    };
    kopia-backup-all = {
      owner = config.users.users.eric.name;
      group = config.users.users.eric.group;
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
    firewall.enable = false;
  };

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    useXkbConfig = false;
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/kuckynas.yaml";
    age.sshKeyPaths = [ "${config.users.users.eric.home}/.ssh/id_ed25519_sops" ];
    secrets = {
      upsmon_user_pw.neededForUsers = true;
      upsmon_user_hashed_pw.neededForUsers = true;
      tailscale_auth.neededForUsers = true;
      eric_icloud_username.owner = "eric";
    };
  };

  users = {
    users = {
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
        initialPassword = "pass";
        openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];
      };

      upsmon = {
        isSystemUser = true;
        hashedPasswordFile = config.sops.secrets.upsmon_user_hashed_pw.path;
        group = "upsmon";
      };
    };

    groups = {
      upsmon = { };
    };
  };

  environment.systemPackages = with pkgs; [
    wireguard-go
    eternal-terminal
    lm_sensors
    zfs
    sops
    unstable.gphotos-sync
    unstable.icloudpd
    unstable.immich-go
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

    samba = {
      enable = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "KuckyNas";
          "netbios name" = "KuckyNas";
          security = "user";
          "hosts allow" = [
            "192.168.1."
            "127.0.0.1"
            "localhost"
          ];
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "bad user";
        };
        public = {
          path = "/kuckyjar/shares/public";
          public = "yes";
          "read only" = "true";
          writeable = "no";
          browseable = "yes";
          "guest ok" = "yes";
          "force user" = "eric";
          "force group" = "users";
        };
      };
    };

    samba-wsdd = {
      enable = true;
    };

    tailscale = {
      enable = true;
      authKeyFile = config.sops.secrets.tailscale_auth.path;
      useRoutingFeatures = "server";
      extraUpFlags = [ "--advertise-routes=192.168.1.0/24" ];
    };
  };

  power.ups = rec {
    enable = true;
    mode = "standalone";

    users.upsmon = {
      passwordFile = config.sops.secrets.upsmon_user_pw.path;
      upsmon = "primary";
    };

    ups = {
      cyberpower = {
        driver = "usbhid-ups";
        port = "auto";
        description = "CP1500 AVR UPS";
        directives = [
          "vendorid = 0764"
          "productid = 0501"
        ];
      };
    };

    upsmon.monitor.cyberpower.user = config.users.users.upsmon.name;
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
