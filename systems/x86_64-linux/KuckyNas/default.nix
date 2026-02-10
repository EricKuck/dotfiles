{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:
let
  allCaddyUrls = lib.custom.hostedUrls {
    inherit config;
    includeScheme = false;
  };

  podmanCaddyUrls = lib.custom.hostedUrls {
    inherit config;
    includeScheme = false;
    includeDirectCaddyUrls = false;
  };

  podmanVirtualHosts = lib.listToAttrs (
    map (
      item:
      lib.nameValuePair item.url {
        extraConfig = ''
          import tls
          reverse_proxy http://localhost:${toString item.port}
        '';
        blackbox.disabled = item.blackboxDisabled;
      }
    ) (builtins.filter (item: item.port != null) podmanCaddyUrls.all)
  );

  irlCiAndroidBuildTools = "36.0.0";
  irlCiAndroidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ irlCiAndroidBuildTools ];
    platformVersions = [ "36" ];
    platformToolsVersion = "36.0.2";
    ndkVersions = [ "29.0.14206865" ];
  };
in
{
  imports = [
    ./ports.nix
    ./uids.nix
    ./observability
    ./matrix
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

  meta = {
    ipAddress = "192.168.1.2";
    containerData = "/kuckyjar/container";
    containerCache = "/kuckyjar/container-cache";
  };

  nixpkgs.config = {
    permittedInsecurePackages = [ "olm-3.2.16" ];
    android_sdk.accept_license = true;
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
      systemd.enable = true;
    };

    kernelModules = [ "kvm-intel" ];
    kernelPackages = pkgs.linuxPackages_6_18;
    kernelParams = [
      "zfs.zfs_arc_max=13958643712" # 13GB: 2GB + 1GB/TB in pool
      "zswap.enabled=1"
      "zswap.compressor=lz4"
      "zswap.max_pool_percent=20"
      "zswap.shrinker_enabled=1"
    ];
    kernel.sysctl = {
      "vm.swappiness" = 30;
      "vm.vfs_cache_pressure" = 50;
      "fs.inotify.max_user_instances" = 1024;
    };
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
      package = pkgs.unstable.zfs_2_4; # TODO: re-evaluate when back on an LTS kernel
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
      size = 16 * 1024;
    }
  ];

  networking = {
    hostId = "219f142e";
    useDHCP = false;
    interfaces.enp6s0.ipv4.addresses = [
      {
        address = config.meta.ipAddress;
        prefixLength = 24;
      }
    ];
    # The flood of dns lookups from blackbox makes viewing adguard stats obnoxious, just hostfile locally hosted stuff
    extraHosts = builtins.concatStringsSep "\n" (
      builtins.map (host: "127.0.0.1 ${host}") (builtins.map (x: x.url) allCaddyUrls.all)
    );
  };

  hardware = {
    cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
    bluetooth.enable = true;
  };

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
      mxroute-server = { };
      mxroute-username = { };
      mxroute-apikey = { };
      mxroute-emails = { };
      immich_api_key.owner = config.meta.flake.owner;
      eric_icloud_username.owner = config.meta.flake.owner;
      karakeep_env.owner = config.meta.flake.owner;
      immich_server_env.owner = config.meta.flake.owner;
      immich_db_env.owner = config.meta.flake.owner;
      rmfakecloud_env.owner = config.meta.flake.owner;
      paperless_env.owner = config.meta.flake.owner;
      paperless_postgres_env.owner = config.meta.flake.owner;
      vaultwarden_env.owner = config.meta.flake.owner;
      booklore_env.owner = config.meta.flake.owner;
      booklore-db_env.owner = config.meta.flake.owner;
      notesnook_env.owner = config.meta.flake.owner;
      multi-scrobbler_env.owner = config.meta.flake.owner;
      bitwarden_mxroute_env.owner = config.meta.flake.owner;
      matrix-synapse-config = { };
      matrix-mas-config = { };
      matrix-mas-signing-key = { };
      matrix-mas-encryption-key = { };
      mautrix-signal-pickle-key = { };
      mautrix-gvoice-pickle-key = { };
      mautrix-gmessages-pickle-key = { };
      mautrix-discord-pickle-key = { };
      mautrix-slack-pickle-key = { };
      doublepuppet-as-token = { };
      doublepuppet-hs-token = { };
    };
    templates."mautrix-signal-env".content = ''
      MAUTRIX_SIGNAL_PICKLE_KEY=${config.sops.placeholder.mautrix-signal-pickle-key}
      DOUBLEPUPPET_TOKEN=as_token:${config.sops.placeholder.doublepuppet-as-token}
    '';
    templates."mautrix-gvoice-env".content = ''
      MAUTRIX_GVOICE_PICKLE_KEY=${config.sops.placeholder.mautrix-gvoice-pickle-key}
      DOUBLEPUPPET_TOKEN=as_token:${config.sops.placeholder.doublepuppet-as-token}
    '';
    templates."mautrix-gmessages-env".content = ''
      MAUTRIX_GMESSAGES_PICKLE_KEY=${config.sops.placeholder.mautrix-gmessages-pickle-key}
      DOUBLEPUPPET_TOKEN=as_token:${config.sops.placeholder.doublepuppet-as-token}
    '';
    templates."mautrix-discord-env".content = ''
      MAUTRIX_DISCORD_PICKLE_KEY=${config.sops.placeholder.mautrix-discord-pickle-key}
      DOUBLEPUPPET_TOKEN=as_token:${config.sops.placeholder.doublepuppet-as-token}
    '';
    templates."mautrix-slack-env".content = ''
      MAUTRIX_SLACK_PICKLE_KEY=${config.sops.placeholder.mautrix-slack-pickle-key}
      DOUBLEPUPPET_TOKEN=as_token:${config.sops.placeholder.doublepuppet-as-token}
    '';
  };

  users = {
    users = {
      "${config.meta.flake.owner}".openssh.authorizedKeys.keys = [ (builtins.readFile keys/ekMBP.pub) ];

      caddy.extraGroups = [ "podman" ];
    };

    groups = { };
  };

  environment.systemPackages = with pkgs; [
    unstable.zfs_2_4 # TODO: re-evaluate using unstable once back on LTS kernel
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
        ];
        hash = "sha256-Rw2zrODQE1Ljgb4FenqUb3LmaNQUTp7h2/tXyjufClY=";
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
      extraConfig = ''
        (tls) {
          tls {
            dns cloudflare {env.CF_DNS_TOKEN}
            resolvers 1.1.1.1 8.8.8.8
          }
        }
      '';
      globalConfig = ''
        skip_install_trust
      '';
    };

    caddy-with-blackbox.virtualHosts = {
      "dns.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://192.168.1.1
      '';
      "z2m.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://192.168.1.3:8080
      '';
      "glance2.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://192.168.1.3:61208
      '';
      "kopia.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:51515
      '';
      "unifi.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy https://localhost:${toString config.ports.unifi} {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
      "scrypted.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy https://localhost:${toString config.ports.scrypted} {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
      "alloy.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:${toString config.ports.alloy}
      '';
      "prom.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:${toString config.ports.prometheus}
      '';
      "alerts.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:${toString config.ports.prometheus-alertmanager}
      '';
      "grafana.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:${toString config.ports.grafana}
      '';
      "glances.kuck.ing".extraConfig = ''
        import tls
        reverse_proxy http://localhost:${toString config.ports.glances}
      '';
      "forwarders.kuck.ing" = {
        extraConfig = ''
          import tls
          reverse_proxy http://localhost:${toString config.ports.mxroute-manager}
        '';
        blackbox.disabled = true;
      };
    }
    // podmanVirtualHosts;

    custom.mxroute-manager = {
      enable = true;
      port = config.ports.mxroute-manager;
      mxrouteServer = config.sops.secrets.mxroute-server.path;
      mxrouteUsername = config.sops.secrets.mxroute-username.path;
      mxrouteApiKeyFile = config.sops.secrets.mxroute-apikey.path;
      allowedEmailsFile = config.sops.secrets.mxroute-emails.path;
    };

    custom.gha-runner.runners = {
      irl1 = {
        url = "https://github.com/Infinite-Retry";
        androidPackages = irlCiAndroidComposition;
        extraPackages = with pkgs; [
          git-lfs
          zulu17
          firebase-tools
          gawk
          jq
          curl
        ];
        environment = {
          "ANDROID_HOME" = "${irlCiAndroidComposition.androidsdk}/libexec/android-sdk";
          "JAVA_HOME" = "${pkgs.zulu17}";
          GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${irlCiAndroidComposition.androidsdk}/libexec/android-sdk/build-tools/${irlCiAndroidBuildTools}/aapt2";
        };
        gradleProperties = {
          "org.gradle.java.installations.paths" = "${pkgs.zulu17}";
          "org.gradle.java.home" = "${pkgs.zulu17}";
          "systemProp.jna.library.path" = lib.makeLibraryPath [ pkgs.udev ];
        };
      };
    };
  };

  system = {
    # NEVER change this value after the initial install, for any reason,
    stateVersion = "23.11"; # Did you read the comment?
  };
}
