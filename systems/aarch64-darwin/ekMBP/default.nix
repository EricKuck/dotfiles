{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
let
  kuckyNasConfig = inputs.self.nixosConfigurations.KuckyNas.config;
  kuckyNasIp = kuckyNasConfig.meta.ipAddress;
  caddyHosts = builtins.attrNames kuckyNasConfig.services.caddy.virtualHosts;
  hostLines = builtins.concatStringsSep "\n" (
    builtins.map (host: "${kuckyNasIp} ${host}") caddyHosts
  );
  irlBuildConfig = inputs.self.darwinConfigurations.IRLBuild.config;
  # Remote socket paths are what `rex server status` reports on each machine; the
  # Linux ones are under uid 1000's runtime dir.
  rexTunnels = {
    kuckynas = {
      address = kuckyNasIp;
      socket = "/run/user/1000/rex/server.sock";
    };
    kuckythings = {
      address = inputs.self.nixosConfigurations.KuckyThings.config.meta.ipAddress;
      socket = "/run/user/1000/rex/server.sock";
    };
    irlbuild = {
      address = irlBuildConfig.meta.ipAddress;
      socket = "${irlBuildConfig.meta.flake.ownerHome}/Library/Application Support/rex/server.sock";
    };
  };
  hostsFile = pkgs.writeText "kuckynas-hosts" ''
    127.0.0.1       localhost
    255.255.255.255 broadcasthost
    ::1             localhost

    ${hostLines}
  '';
in
with lib.custom;
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  custom = {
    environments = {
      common.enable = true;
      workstation.enable = true;
      android.enable = true;
      ios.enable = true;
      rust.enable = true;
      backups.enable = true;
    };

    programs = {
      nh.enable = true;
      rex.enable = true;
    };
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/ekmbp.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
    secrets = {
      btt_license = { };
      istat_menus_license = { };
      mqtt_creds.owner = config.meta.flake.owner;
    };
  };

  environment.systemPackages = with pkgs; [
    sops
  ];

  homebrew = {
    brews = [
      "emin-ozata/homebrew-tap/lazycut"
      "pi-coding-agent"
    ];

    casks = [
      "bambu-studio"
      "winbox"
      "autodesk-fusion"
      "openscad@snapshot"
      "signal"
      "vial"
      "utm"
      "zed"
      "obs"
      "vivaldi"
      "visualvm"
      "netnewswire"
      "stablyai/orca/orca"
    ];

    masApps = {
      "MQTT Explorer" = 1455214828;
      PagerCall = 6740581987;
      Reeder = 1449412482;
    };
  };

  # Forwards each machine's personal Rex server socket to a local one, since Rex has
  # no authenticated LAN listener. Add ~/.ssh/rex-<name>.sock as a remote host in Rex.
  # macOS's ssh is used so a key passphrase can come from the keychain.
  launchd.user.agents = lib.mapAttrs' (
    name: tunnel:
    lib.nameValuePair "rex-${name}-tunnel" {
      serviceConfig = {
        ProgramArguments = [
          "/usr/bin/ssh"
          "-N"
          "-o"
          "BatchMode=yes"
          "-o"
          "ConnectTimeout=10"
          "-o"
          "ExitOnForwardFailure=yes"
          "-o"
          "ServerAliveInterval=30"
          "-o"
          "ServerAliveCountMax=3"
          "-o"
          "StreamLocalBindUnlink=yes"
          "-o"
          "StreamLocalBindMask=0177"
          "-L"
          "${config.meta.flake.ownerHome}/.ssh/rex-${name}.sock:${tunnel.socket}"
          "${config.meta.flake.owner}@${tunnel.address}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardErrorPath = "${config.meta.flake.ownerHome}/Library/Logs/rex-${name}-tunnel.log";
      };
    }
  ) rexTunnels;

  system.activationScripts.postActivation.text = ''
    cp ${hostsFile} /etc/hosts
  '';

  system.stateVersion = 6;
}
