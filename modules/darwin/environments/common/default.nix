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

  wallpaper = builtins.path {
    path = ./StarrySur_Mac.png;
    name = "StarrySur_Mac.png";
  };

  codeIcon = builtins.path {
    path = ./Code.icns;
    name = "Code.icns";
  };

  fileicon = builtins.path {
    path = ./fileicon;
    name = "fileicon";
  };

  codeVolume = "Code";
  codeMountPoint = "/Users/eric/Code";
  codeMountOptions = "rw,noauto,nobrowse,suid,owners";
  codeKeychainEntry = "CodeVolume";
in
{
  options.custom.environments.common = {
    enable = mkEnableOption "common";
  };

  config = mkIf cfg.enable {
    system = {
      activationScripts.userScript.text = ''
        #!${lib.getExe pkgs.bash}
        echo >&2 "wallpaper..."
        osascript -e 'tell application "Finder" to set desktop picture to POSIX file "${wallpaper}"'

        echo >&2 "code dir..."
        FILEICON=${fileicon}
        CODE_ICNS=${codeIcon}
        VOLUME=${codeVolume}
        MOUNT_POINT="${codeMountPoint}"
        MOUNT_OPTIONS=${codeMountOptions}
        KEYCHAIN_ENTRY="${codeKeychainEntry}"
        ${builtins.readFile ./mk_code_volume.sh}

        echo >&2 "disabling text replacements..."
        defaults write -g NSUserDictionaryReplacementItems -array
      '';

      defaults = {
        dock = {
          autohide = true;
          tilesize = 51;
          largesize = 58;
          magnification = true;
        };

        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          NSAutomaticSpellingCorrectionEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false;
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          ApplePressAndHoldEnabled = false;
          AppleEnableSwipeNavigateWithScrolls = false;
          "com.apple.trackpad.forceClick" = false;
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
            "wvous-br-corner" = 1;
            "wvous-br-modifier" = 0;
          };
          "com.apple.finder" = {
            ShowExternalHardDrivesOnDesktop = true;
            ShowHardDrivesOnDesktop = true;
            ShowMountedServersOnDesktop = true;
            ShowRemovableMediaOnDesktop = true;
            QuitMenuItem = true;
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
            ForceSuppressed = true;
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
            ForceSuppressed = true;
          };
          "com.apple.TextEdit" = {
            RichText = 0;
          };
          "com.apple.symbolichotkeys" = {
            AppleSymbolicHotKeys = {
              "7".enabled = 0;
              "8".enabled = 0;
              "9".enabled = 0;
              "10".enabled = 0;
              "11".enabled = 0;
              "12".enabled = 0;
              "13".enabled = 0;
              "32".enabled = 0;
              "33".enabled = 0;
              "57".enabled = 0;
              "79".enabled = 0;
              "81".enabled = 0;
              # Disable dictation
              "164".enabled = 0;
              # opt-space for spotlight
              "64" = {
                enabled = 1;
                value = {
                  parameters = [
                    32
                    49
                    524288
                  ];
                  type = "standard";
                };
              };
            };
          };
        };
      };
    };

    launchd = {
      user = {
        agents = {
          mount-code-volume = {
            command = "/usr/bin/security find-generic-password -s \"${codeKeychainEntry}\" -w | /usr/sbin/diskutil apfs unlockVolume ${codeVolume} -nomount -stdinpassphrase && /usr/sbin/diskutil mount -mountOptions ${codeMountOptions} -mountPoint ${codeMountPoint} ${codeVolume}";
            serviceConfig = {
              RunAtLoad = true;
            };
          };
        };
      };
    };

    programs.fish.enable = true;

    environment = {
      shells = [ pkgs.fish ];
      systemPath = [ "/opt/homebrew/bin" ];
      systemPackages = [ pkgs.custom.micswitch ];
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
        "arc"
        "battery"
        "obsidian"
        "macmediakeyforwarder"
        "spotify"
        "lulu"
        "intellij-idea-ce"
        "force-paste"
        "kitty"
        "wezterm"
        "raycast"
        "jordanbaird-ice"
        "visual-studio-code"
        "istat-menus"
        "docker"
        "mullvadvpn"
        "maccy"
        "soduto"
        "bettertouchtool"
      ];

      masApps = {
        Slack = 803453959;
        Gifski = 1351639930;
      };
    };

    fonts.packages = [ (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; }) ];
  };
}
