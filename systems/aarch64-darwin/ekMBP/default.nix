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

  # Forwards KuckyNas's personal Rex server socket to a local one, since Rex has no
  # authenticated LAN listener. Add the local socket path as a remote host in Rex.
  # macOS's ssh is used so a key passphrase can come from the keychain.
  launchd.user.agents.rex-kuckynas-tunnel.serviceConfig = {
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
      # uid 1000, as reported by `rex server status` on KuckyNas.
      "${config.meta.flake.ownerHome}/.ssh/rex-kuckynas.sock:/run/user/1000/rex/server.sock"
      "${config.meta.flake.owner}@${kuckyNasIp}"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 30;
    StandardErrorPath = "${config.meta.flake.ownerHome}/Library/Logs/rex-kuckynas-tunnel.log";
  };

  system.activationScripts.postActivation.text = ''
    cp ${hostsFile} /etc/hosts
  '';

  system.stateVersion = 6;
}
