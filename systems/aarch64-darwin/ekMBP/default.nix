{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  environment = {
    shells = [ pkgs.fish ];

    systemPath = [ "/opt/homebrew/bin" ];

    shellAliases = {
      kopia = "/Applications/KopiaUI.app/Contents/Resources/server/kopia";
      gw = "gww";
    };
  };

  programs.fish.enable = true;

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

    taps = [
      "mdogan/zulu"
      "pbreault/gww"
    ];

    brews = [
      "gradle-profiler"
      "pbreault/gww/gww"
    ];

    casks = [
      "1password"
      "kopiaui"
      "flipper"
      "orcaslicer"
      "obsidian"
      "nrlquaker-winbox"
      "macmediakeyforwarder"
      "spotify"
      "lulu"
      "android-studio"
      "intellij-idea-ce"
      "kaleidoscope"
      "force-paste"
      "kitty"
      "raycast"
      "bartender"
      "visual-studio-code"
      "istat-menus"
      "zulu-jdk17"
    ];
  };

  users.users.erickuck = rec {
    home = "/Users/${config.users.users.erickuck.name}";
  };

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
          FXPreferredViewStyle = "clmv";
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

    stateVersion = 4;
  };
}
