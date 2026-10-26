{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:

# The macOS VM on IRLBuild that hosts iMessage for the Matrix bridge: Messages
# signed into the Apple Account, plus BlueBubbles Server with its Private API.
# SIP is disabled here (by packages/imessage-vm-image) so the Private API can
# inject into Messages; mautrix-imessage itself runs on KuckyNas.
#
# Built with `imessage-vm-image`, deployed from IRLBuild with
# `imessage-vm-deploy`; see README.md for the one-time manual steps.
let
  owner = config.meta.flake.owner;
  home = config.meta.flake.ownerHome;
  bluebubblesApp = "/Applications/Nix Apps/BlueBubbles.app";
in
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  # Not `common`: that one assumes Homebrew and a workstation.
  custom.environments.server.enable = true;

  system.primaryUser = owner;

  networking = {
    hostName = "imessage-bridge";
    computerName = "imessage-bridge";
    localHostName = "imessage-bridge";
  };

  # Deploys copy the system closure over from IRLBuild.
  nix.settings.trusted-users = [ owner ];

  users.users.${owner}.openssh.authorizedKeys.keyFiles = lib.fileset.toList (
    lib.fileset.fileFilter (file: file.hasExt "pub") ./keys
  );

  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  power.sleep.display = "never";

  system.defaults = {
    CustomSystemPreferences = {
      # The Private API helper is injected into Messages.app.
      "/Library/Preferences/com.apple.security.libraryvalidation".DisableLibraryValidation = true;

      # Updates go in by hand: a new macOS tends to break the Private API
      # until BlueBubbles catches up.
      "/Library/Preferences/com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = false;
        AutomaticDownload = false;
        AutomaticallyInstallMacOSUpdates = false;
        ConfigDataInstall = false;
        CriticalUpdateInstall = false;
      };
      "/Library/Preferences/com.apple.commerce".AutoUpdate = false;
    };
  };

  # Screen Sharing, for signing into the Apple Account and granting
  # permissions. Reached through IRLBuild's port forward.
  system.activationScripts.postActivation.text = ''
    echo >&2 "screen sharing..."
    launchctl enable system/com.apple.screensharing
    launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  '';

  sops = {
    defaultSopsFile = lib.snowfall.fs.get-file "secrets/imessage_bridge.yaml";
    age.sshKeyPaths = [ "${home}/.ssh/id_ed25519_sops" ];
    secrets.bluebubbles-password = { };

    # BlueBubbles applies ~/bluebubbles.yml over its own settings at startup.
    # JSON, since YAML is a superset of it.
    templates."bluebubbles.yml" = {
      path = "${home}/bluebubbles.yml";
      owner = owner;
      mode = "0400";
      content = builtins.toJSON {
        password = config.sops.placeholder.bluebubbles-password;
        socket_port = 1234;
        # Only reachable over the LAN, through IRLBuild; no tunnels.
        proxy_service = "lan-url";
        enable_private_api = true;
        tutorial_is_done = true;
        # launchd starts it, and the app bundle is read-only anyway.
        auto_start = false;
        check_for_updates = false;
        auto_install_updates = false;
        auto_caffeinate = true;
        start_minimized = true;
        open_findmy_on_startup = false;
      };
    };
  };

  environment.systemPackages = [ pkgs.custom.bluebubbles-server ];

  launchd.user.agents.bluebubbles = {
    # Waits for sops-nix so the first start isn't unconfigured, and launches
    # through LaunchServices so macOS attributes its permissions to the app.
    script = ''
      while [ ! -e ${home}/bluebubbles.yml ]; do sleep 1; done
      exec /usr/bin/open -W -a "${bluebubblesApp}"
    '';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
    };
  };

  system.stateVersion = 6;
}
