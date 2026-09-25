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
  };

  networking = {
    hostName = "IRLBuild";
    computerName = "IRLBuild";
    localHostName = "IRLBuild";
  };

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/irlbuild.yaml";
    age.sshKeyPaths = [ "${config.meta.flake.ownerHome}/.ssh/id_ed25519_sops" ];
    secrets = lib.genAttrs (map (name: "gha-runner-${name}-token") runners) (_: {
      key = "gha-runner-token";
    });
  };

  gha-runner.irl.runners = lib.genAttrs runners (name: {
    tokenFile = config.sops.secrets."gha-runner-${name}-token".path;
  });

  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  environment.systemPackages = with pkgs; [
    sops
  ];

  system.stateVersion = 6;
}
