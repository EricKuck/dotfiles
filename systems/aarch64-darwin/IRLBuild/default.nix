{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
let
  runners = [
    "irl-macos-1"
    "irl-macos-2"
  ];
  # Registered with the RIPcord repository only, so other repositories' jobs
  # never land on an ephemeral runner.
  ripcordRunners = [ "ripcord-macos-1" ];
in
with lib.custom;
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  custom = {
    environments = {
      common.enable = true;
      server.enable = true;
      ios.enable = true;
    };

    # The imessage-bridge VM: Messages + BlueBubbles for the iMessage bridge on
    # KuckyNas. Built with `imessage-vm-image`, deployed with
    # `imessage-vm-deploy`.
    services.tart-vms.vms.imessage-bridge.forwardPorts = [
      # BlueBubbles, for mautrix-imessage on KuckyNas.
      {
        host = 1234;
        guest = 1234;
      }
      {
        host = 2222;
        guest = 22;
      }
      # Screen Sharing; 5900 is IRLBuild's own.
      {
        host = 5901;
        guest = 5900;
      }
    ];
  };

  meta.ipAddress = "192.168.1.23";

  networking = {
    hostName = "IRLBuild";
    computerName = "IRLBuild";
    localHostName = "IRLBuild";
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/irlbuild.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
    secrets =
      lib.genAttrs (map (name: "gha-runner-${name}-token") runners) (_: {
        key = "gha-runner-token";
      })
      // lib.genAttrs (map (name: "gha-runner-${name}-token") ripcordRunners) (_: {
        key = "gha-runner-ripcord-token";
      })
      // {
        immich-photo-sync-api-key.owner = config.meta.flake.owner;
        uptime-slack-webhook-url.owner = config.meta.flake.owner;
        uptime-heartbeat-url.owner = config.meta.flake.owner;
      };
  };

  gha-runner.irl.runners =
    lib.genAttrs runners (name: {
      tokenFile = config.sops.secrets."gha-runner-${name}-token".path;
    })
    // lib.genAttrs ripcordRunners (name: {
      tokenFile = config.sops.secrets."gha-runner-${name}-token".path;
      url = "https://github.com/Infinite-Retry/RIPcord";
      ephemeral = true;
      extraLabels = [ "ripcord" ];
    });

  custom.services.immich-photo-sync = {
    enable = true;
    server = "https://immich.kuck.ing";
    apiKeyFile = config.sops.secrets.immich-photo-sync-api-key.path;
  };

  custom.services.uptime-monitor = {
    enable = true;
    # KuckyNas's Grafana reads this as a data source.
    listenAddress = "0.0.0.0:9090";
    slackWebhookUrlFile = config.sops.secrets.uptime-slack-webhook-url.path;
    heartbeatUrlFile = config.sops.secrets.uptime-heartbeat-url.path;
    probes.ripcord = {
      url = "https://crash.infiniteretry.com/healthz";
      bodyRegex = "^ok$";
    };
  };

  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  environment.systemPackages = with pkgs; [
    sops
    lynx
    custom.imessage-vm-image
    custom.imessage-vm-deploy
  ];

  system.stateVersion = 6;
}
