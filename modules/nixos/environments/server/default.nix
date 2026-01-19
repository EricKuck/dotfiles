{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.server;

  userScriptSnippets = lib.mapAttrsToList (
    name: container:
    let
      containerConfig = container.containerConfig or { };
      user = containerConfig.user or null;
      fsOwner =
        if user != null then
          let
            parts = lib.splitString ":" user;
            uid = lib.toInt (builtins.elemAt parts 0);
            gid = lib.toInt (builtins.elemAt parts 1);
          in
          "${toString (uid + 99999)}:${toString (gid + 99999)}"
        else
          null;

      ownedVolumes =
        builtins.map
          (
            vol:
            let
              src = builtins.elemAt (lib.splitString ":" vol) 0;
            in
            src
          )
          (
            builtins.filter (
              vol:
              let
                src = builtins.elemAt (lib.splitString ":" vol) 0;
              in
              lib.hasPrefix config.meta.containerData src
            ) containerConfig.volumes
          );
    in
    if fsOwner != null then
      ''
        if [ -d "${config.meta.containerData}" ]; then
          DIR_PATHS=(${lib.strings.concatStringsSep " " (map (dir: builtins.toJSON dir) ownedVolumes)})
          for DIR_PATH in "''${DIR_PATHS[@]}"; do
            PERMS=$(stat -c "%a" "$DIR_PATH")
            if [ "$PERMS" != "700" ]; then
              echo "🚨🚨 $DIR_PATH permissions, used for ${name}, are wrong: $PERMS. Should be 700." >&2
            fi
            OWNER=$(stat -c "%u:%g" "$DIR_PATH")
            if [ "$OWNER" != "${fsOwner}" ]; then
              echo "🚨🚨 $DIR_PATH ownership, used for ${name} is wrong: $OWNER. Should be ${fsOwner}." >&2
            fi
          done
        fi
      ''
    else
      ""
  ) config.home-manager.users."${config.meta.flake.owner}".quadlets.containers;
in
{
  options.custom.environments.server = {
    enable = mkEnableOption "server";
    quadlets = {
      enable = mkEnableOption "quadlets";
    };
    tailscale = {
      enable = mkEnableOption "tailscale";
      authKeyFile = lib.mkOption {
        type = lib.types.path;
      };
    };
    ups = {
      enable = mkEnableOption "ups";
      upsmonUserPass = lib.mkOption {
        type = lib.types.path;
      };
      upsmonHashedUserPass = lib.mkOption {
        type = lib.types.path;
      };
    };
  };

  config = mkIf cfg.enable {
    custom.programs.nh.enable = true;

    security.wrappers = {
      kopia = {
        owner = config.meta.flake.owner;
        group = config.users.users."${config.meta.flake.owner}".group;
        capabilities = "cap_dac_read_search=+ep";
        source = lib.getExe' pkgs.kopia "kopia";
      };
    };

    networking = {
      networkmanager.enable = true;
      useDHCP = lib.mkDefault true;
      dhcpcd.IPv6rs = false;
      enableIPv6 = false;
      defaultGateway = "192.168.1.1";
      nameservers = [ "172.17.0.2" ];
      firewall.enable = false;
    };

    time.timeZone = config.meta.timezone;
    i18n.defaultLocale = "en_US.UTF-8";
    console = {
      font = "Lat2-Terminus16";
      keyMap = "us";
      useXkbConfig = false;
    };

    users = {
      users = {
        root = {
          hashedPassword = "!";
        };

        "${config.meta.flake.owner}" = {
          isNormalUser = true;
          extraGroups = [
            "wheel"
          ]
          ++ lib.optional cfg.quadlets.enable "podman";
          shell = pkgs.fish;
          linger = true;
          autoSubUidGidRange = true;
          initialPassword = "pass";
        };

        upsmon = mkIf cfg.ups.enable {
          isSystemUser = true;
          hashedPasswordFile = cfg.ups.upsmonHashedUserPass;
          group = "upsmon";
        };
      };

      groups = {
        podman = mkIf cfg.quadlets.enable { };
        upsmon = mkIf cfg.ups.enable { };
      };
    };

    environment.systemPackages = with pkgs; [
      wireguard-go
      eternal-terminal
      shpool
      lm_sensors
      sops
    ];

    programs = {
      fish.enable = true;
    };

    services = {
      resolved = {
        enable = true;
        fallbackDns = [ ];
      };

      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      eternal-terminal.enable = true;
      glances.enable = true;

      tailscale = mkIf cfg.tailscale.enable {
        enable = true;
        authKeyFile = cfg.tailscale.authKeyFile;
        useRoutingFeatures = "server";
        extraUpFlags = [ "--advertise-routes=192.168.1.0/24" ];
      };
    };

    power.ups = mkIf cfg.ups.enable {
      enable = true;
      mode = "standalone";

      users.upsmon = {
        passwordFile = cfg.ups.upsmonUserPass;
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

    systemd = {
      sockets = {
        podman-rootless-proxy = mkIf cfg.quadlets.enable {
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
        podman-rootless-proxy = mkIf cfg.quadlets.enable {
          enable = true;
          description = "Proxy to rootless podman socket";
          serviceConfig = {
            ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd /run/user/1000/podman/podman.sock";
            User = config.meta.flake.owner;
            Group = "users";
            Restart = "on-failure";
          };
          requires = [ "podman.socket" ];
          after = [ "default.target" ];
        };

        tailscaled = mkIf cfg.tailscale.enable {
          after = [ "systemd-networkd-wait-online.service" ];
        };
      };

      targets.network-online.wantedBy = [ "multi-user.target" ];
    };

    virtualisation = mkIf cfg.quadlets.enable {
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
      quadlet.enable = true;
    };

    system.activationScripts.userScript.text = mkIf cfg.quadlets.enable (
      lib.concatStringsSep "\n" (lib.filter (s: s != "") userScriptSnippets)
    );
  };
}
