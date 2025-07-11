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
  imports = [
    ./ports.nix
    ./observability
    inputs.sops-nix.nixosModules.sops
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  custom = {
    environments.server = {
      enable = true;
      quadlets.enable = true;
      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets.tailscale_auth.path;
      };
      ups = {
        enable = true;
        upsmonUserPass = config.sops.secrets.upsmon_user_pw.path;
        upsmonHashedUserPass = config.sops.secrets.upsmon_user_hashed_pw.path;
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

  networking.hostId = "219f142e";

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/kuckynas.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
    secrets = {
      upsmon_user_pw = {
        mode = "0440";
        group = config.users.groups.upsmon.name;
      };
      upsmon_user_hashed_pw.neededForUsers = true;
      tailscale_auth.neededForUsers = true;
      caddy_env = { };
      immich_api_key.owner = config.meta.flake.owner;
      eric_icloud_username.owner = config.meta.flake.owner;
      karakeep_env.owner = config.meta.flake.owner;
      immich_server_env.owner = config.meta.flake.owner;
      immich_db_env.owner = config.meta.flake.owner;
      rmfakecloud_env.owner = config.meta.flake.owner;
      paperless_env.owner = config.meta.flake.owner;
      paperless_postgres_env.owner = config.meta.flake.owner;
      vaultwarden_env.owner = config.meta.flake.owner;
      obsidian-sync_env.owner = config.meta.flake.owner;
    };
  };

  users = {
    users = {
      "${config.meta.flake.owner}".openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];

      caddy.extraGroups = [ "podman" ];
    };
  };

  environment.systemPackages = with pkgs; [
    unstable.zfs # TODO: re-evaluate using unstable once back on LTS kernel
    unstable.icloudpd
    unstable.immich-go
  ];

  services = {
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
          "force user" = config.meta.flake.owner;
          "force group" = "users";
        };
      };
    };

    samba-wsdd = {
      enable = true;
    };

    caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.1"
          "github.com/EricKuck/caddy-docker-upstreams@v0.0.0-20250616194924-027669749ea0"
        ];
        hash = "sha256-sjJJu6wRGMq7qStWHMLTRY36gRZfbp1D+G6vlQ5xc28=";
      };
      logFormat = ''
        output file /var/log/caddy/access.log {
          mode 640
        }
        level INFO
        format filter {
          request>headers>Cookie cookie {
            replace session REDACTED
            delete secret
          }
        }
      '';
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
        "alloy.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.alloy}
        '';
        "prom.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.prometheus}
        '';
        "alerts.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.prometheus-alertmanager}
        '';
        "grafana.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.grafana}
        '';
        "glances.kuck.ing".extraConfig = ''
          reverse_proxy http://localhost:${toString config.ports.glances}
        '';
        "*.kuck.ing".extraConfig = ''
          reverse_proxy {
            dynamic docker
          }
        '';
      };
    };
  };

  systemd = {
    services = {
      caddy = {
        environment = {
          DOCKER_HOST = "unix:///run/podman-rootless-proxy/podman.sock";
        };
      };
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
