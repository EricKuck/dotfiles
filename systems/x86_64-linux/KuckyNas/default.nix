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
    ./ports.nix
    ./observability
    "${inputs.nixpkgs-unstable}/nixos/modules/services/monitoring/ups.nix"
    inputs.sops-nix.nixosModules.sops
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  custom = {
    programs = {
      nh = {
        enable = true;
        flake = "path:/home/eric/.config/nixos";
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
    kernelPackages = pkgs.linuxPackages_6_13;
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
      package = pkgs.unstable.zfs; # TODO: re-evaluate when back on an LTS kernel
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
      upsmon_user_pw = {
        mode = "0440";
        group = config.users.groups.upsmon.name;
      };
      upsmon_user_hashed_pw.neededForUsers = true;
      tailscale_auth.neededForUsers = true;
      immich_api_key.owner = "eric";
      eric_icloud_username.owner = "eric";
      caddy_env = { };
      karakeep_env.owner = "eric";
      immich_server_env.owner = "eric";
      immich_db_env.owner = "eric";
      rmfakecloud_env.owner = "eric";
      paperless_env.owner = "eric";
      paperless_postgres_env.owner = "eric";
      autokuma_env.owner = "eric";
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
        autoSubUidGidRange = true;
        initialPassword = "pass";
        openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];
      };

      upsmon = {
        isSystemUser = true;
        hashedPasswordFile = config.sops.secrets.upsmon_user_hashed_pw.path;
        group = "upsmon";
      };

      caddy = {
        extraGroups = [ "podman" ];
      };
    };

    groups = {
      upsmon = { };
      podman = { };
    };
  };

  environment.systemPackages = with pkgs; [
    wireguard-go
    eternal-terminal
    lm_sensors
    unstable.zfs # TODO: re-evaluate using unstable once back on LTS kernel
    sops
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

    caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.1"
          "github.com/EricKuck/caddy-docker-upstreams@v0.0.0-20250616194924-027669749ea0"
        ];
        hash = "sha256-Rt8xFp5yvBLsFQILPCX+RPT/nfcR++D1gWelSuuuVBA=";
      };
      environmentFile = config.sops.secrets.caddy_env.path;
      globalConfig = ''
        skip_install_trust
        email {$ACME_EMAIL}
        acme_dns cloudflare {$CF_DNS_TOKEN}
      '';
      virtualHosts = {
        "adguard.kuck.ing".extraConfig = ''
          reverse_proxy http://192.168.1.1
        '';
        "z2m.kuck.ing".extraConfig = ''
          reverse_proxy http://192.168.1.3:8080
        '';
        "kopia.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:51515
        '';
        "uptime.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.uptime-kuma}
        '';
        "unifi.kuck.ing".extraConfig = ''
          reverse_proxy https://localhost:${toString config.ports.unifi} {
            transport http {
              tls_insecure_skip_verify
            }
          }
        '';
        "scrypted.kuck.ing".extraConfig = ''
          reverse_proxy https://localhost:${toString config.ports.scrypted} {
            transport http {
              tls_insecure_skip_verify
            }
          }
        '';
        "prom.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.prometheus}
        '';
        "grafana.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.grafana}
        '';
        "*.kuck.ing".extraConfig = ''
          reverse_proxy {
            dynamic docker
          }
        '';
      };
    };

    uptime-kuma.enable = true;
  };

  systemd = {
    sockets = {
      podman-rootless-proxy = {
        enable = true;
        description = "Socket for proxy to user podman socket";
        socketConfig = {
          ListenStream = "/run/podman-rootless-proxy/podman.sock";
          SocketMode = 660;
          SocketGroup = "podman";
          Service = "podman-rootless-proxy.service";
        };
        requires = [ "podman-rootless-proxy.service" ];
        wantedBy = [ "sockets.target" ];
      };
    };

    services = {
      caddy = {
        environment = {
          DOCKER_HOST = "unix:///run/podman-rootless-proxy/podman.sock";
        };
      };
      tailscaled = {
        after = [ "systemd-networkd-wait-online.service" ];
      };
      podman-rootless-proxy = {
        enable = true;
        description = "Proxy to rootless podman socket";
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd /run/user/1000/podman/podman.sock";
          User = "eric";
          Group = "users";
          Restart = "on-failure";
        };
        requires = [ "podman.socket" ];
        after = [ "default.target" ];
      };
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
    containers = {
      enable = true;
      containersConf.settings.engine.helper_binaries_dir = [
        "${pkgs.netavark}/bin"
        "${pkgs.aardvark-dns}/bin"
        "${pkgs.podman}/libexec/podman"
      ];
    };
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
