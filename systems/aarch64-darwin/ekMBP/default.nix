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
      android.enable = true;
      rust.enable = true;
      backups.enable = true;
    };

    programs = {
      nh.enable = true;
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

  gha-runner.irl.runners = {
    irl-darwin-1.tokenFile = config.sops.secrets.gha-runner-irl-darwin-1-token.path;
  };

  environment.systemPackages = with pkgs; [
    sops
  ];

  homebrew = {
    taps = [
      "BarutSRB/tap"
    ];

    brews = [
      "emin-ozata/homebrew-tap/lazycut"
    ];

    casks = [
      "bambu-studio"
      "winbox"
      "autodesk-fusion"
      "openscad@snapshot"
      "mailspring"
      "signal"
      "inkscape"
      "vial"
      "utm"
      "zed"
      "obs"
      "vivaldi"
      "visualvm"
      "BarutSRB/tap/omniwm"
    ];

    masApps = {
      Tailscale = 1475387142;
      WireGuard = 1451685025;
      Infuse = 1136220934;
      "MQTT Explorer" = 1455214828;
      PagerCall = 6740581987;
    };
  };

  system.activationScripts.postActivation.text = ''
    cp ${hostsFile} /etc/hosts
  '';

  system.stateVersion = 6;
}
