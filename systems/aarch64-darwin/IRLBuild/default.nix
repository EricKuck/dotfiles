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

    services.corten-matrix = {
      enable = true;
      homeserver = {
        address = "https://matrix.kuck.ing";
        domain = "kuck.ing";
      };
      adminUser = "@eric:kuck.ing";

      settings = {
        # Must match the registration Synapse loads (KuckyNas matrix/imessage.nix).
        appservice = {
          as_token = config.sops.placeholder.corten-matrix-as-token;
          hs_token = config.sops.placeholder.corten-matrix-hs-token;
        };

        double_puppet.secrets."kuck.ing" = "as_token:${config.sops.placeholder.doublepuppet-as-token}";
      };
    };
  };

  # KuckyNas builds the appservice registration from this, so it has to stay
  # reachable from there.
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
        corten-matrix-as-token = { };
        corten-matrix-hs-token = { };
        # Same value as on KuckyNas; lets the bridge double-puppet @eric.
        doublepuppet-as-token = { };
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
  ];

  system.stateVersion = 6;
}
