{
  lib,
  pkgs,
  inputs,
  system,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.common;
in
{
  options.custom.environments.common = {
    enable = mkEnableOption "common";
  };

  config = mkIf cfg.enable {
    system = {
      defaults = {
        dock = {
          autohide = true;
          largesize = 58;
          magnification = true;
        };

        NSGlobalDomain = {
          NSAutomaticSpellingCorrectionEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false;
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          AppleInterfaceStyle = "Dark";
          ApplePressAndHoldEnabled = false;
        };

        finder = {
          FXPreferredViewStyle = "clmv";
        };

        loginwindow = {
          GuestEnabled = false;
        };

        CustomUserPreferences = {
          "com.apple.dock" = {
            showDesktopGestureEnabled = false;
            showMissionControlGestureEnabled = false;
            showLaunchpadGestureEnabled = false;
          };
          "com.apple.finder" = {
            ShowExternalHardDrivesOnDesktop = true;
            ShowHardDrivesOnDesktop = true;
            ShowMountedServersOnDesktop = true;
            ShowRemovableMediaOnDesktop = true;
          };
          "com.apple.desktopservices" = {
            # Avoid creating .DS_Store files on network or USB volumes
            DSDontWriteNetworkStores = true;
            DSDontWriteUSBStores = true;
          };
          "com.apple.AdLib" = {
            allowApplePersonalizedAdvertising = false;
          };
          "com.apple.AppleMultitouchTrackpad" = {
            TrackpadTwoFingerFromRightEdgeSwipeGesture = 0;
            TrackpadThreeFingerHorizSwipeGesture = 0;
            TrackpadThreeFingerVertSwipeGesture = 0;
            TrackpadThreeFingerDrag = false;
            TrackpadThreeFingerTapGesture = 0;
            TrackpadFourFingerVertSwipeGesture = 0;
            TrackpadFourFingerHorizSwipeGesture = 0;
            TrackpadFiveFingerPinchGesture = 0;
          };
          "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
            TrackpadTwoFingerFromRightEdgeSwipeGesture = 0;
            TrackpadThreeFingerHorizSwipeGesture = 0;
            TrackpadThreeFingerVertSwipeGesture = 0;
            TrackpadThreeFingerDrag = false;
            TrackpadThreeFingerTapGesture = 0;
            TrackpadFourFingerVertSwipeGesture = 0;
            TrackpadFourFingerHorizSwipeGesture = 0;
            TrackpadFiveFingerPinchGesture = 0;
          };
        };
      };
    };

    programs.fish.enable = true;

    environment = {
      shells = [ pkgs.fish ];
      systemPath = [ "/opt/homebrew/bin" ];
    };

    homebrew = {
      enable = true;

      onActivation = {
        upgrade = true;
        autoUpdate = true;
        cleanup = "zap";
      };

      global = {
        autoUpdate = true;
        brewfile = true;
        lockfiles = true;
      };

      casks = [
        "1password"
        "obsidian"
        "macmediakeyforwarder"
        "spotify"
        "lulu"
        "intellij-idea-ce"
        "kaleidoscope"
        "force-paste"
        "kitty"
        "raycast"
        "bartender"
        "visual-studio-code"
        "istat-menus"
      ];

      masApps = {
        Slack = 803453959;
      };
    };
  };
}
