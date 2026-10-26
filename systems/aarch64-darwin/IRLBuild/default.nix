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
      // {
        immich-photo-sync-api-key.owner = config.meta.flake.owner;
      };
  };

  homebrew = {
    casks = [
      "utm"
    ];
  };

  gha-runner.irl.runners = lib.genAttrs runners (name: {
    tokenFile = config.sops.secrets."gha-runner-${name}-token".path;
  });

  custom.services.immich-photo-sync = {
    enable = true;
    server = "https://immich.kuck.ing";
    apiKeyFile = config.sops.secrets.immich-photo-sync-api-key.path;
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
