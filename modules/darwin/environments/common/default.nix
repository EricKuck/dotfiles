{
  config,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.common;

  wallpaper = builtins.path {
    path = ./configs/wallpaper/StarrySur_Mac.png;
    name = "StarrySur_Mac.png";
  };

  codeIcon = builtins.path {
    path = ./configs/codedir/Code.icns;
    name = "Code.icns";
  };

  fileicon = builtins.path {
    path = ./configs/codedir/fileicon;
    name = "fileicon";
  };

  codeVolume = "Code";
  codeMountPoint = "${config.meta.flake.ownerHome}/Code";
  codeMountOptions = "rw,noauto,nobrowse,suid,owners";
  codeKeychainEntry = "CodeVolume";
in
{
  options.custom.environments.common = {
    enable = mkEnableOption "common";
  };

  config = mkIf cfg.enable {
    system = {
      primaryUser = config.meta.flake.owner;

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
        ${builtins.readFile ./configs/codedir/mk_code_volume.sh}

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
          # Disable builtin keyboard shortcuts
          "pbs" = {
            "com.apple.ChineseTextConverterService - Convert Text from Simplified to Traditional Chinese - convertTextToTraditionalChinese" =
              {
                "enabled_context_menu" = 0;
                "enabled_services_menu" = 0;
                "presentation_modes" = {
                  ContextMenu = 1;
                  ServicesMenu = 0;
                };
              };
            "com.apple.ChineseTextConverterService - Convert Text from Traditional to Simplified Chinese - convertTextToSimplifiedChinese" =
              {
                "enabled_context_menu" = 0;
                "enabled_services_menu" = 0;
                "presentation_modes" = {
                  ContextMenu = 0;
                  ServicesMenu = 0;
                };
              };
            "com.apple.Safari -   Search With %WebSearchProvider@ - searchWithWebSearchProvider" = {
              "enabled_context_menu" = 0;
              "enabled_services_menu" = 0;
              "presentation_modes" = {
                ContextMenu = 0;
                ServicesMenu = 0;
              };
            };
            "com.apple.Stickies - Make Sticky - makeStickyFromTextService" = {
              "enabled_services_menu" = 0;
              "presentation_modes" = {
                ContextMenu = 0;
                ServicesMenu = 0;
              };
            };
            "com.apple.Terminal - Open man Page in Terminal - openManPage" = {
              "enabled_context_menu" = 0;
              "enabled_services_menu" = 0;
              "presentation_modes" = {
                ContextMenu = 0;
                ServicesMenu = 0;
              };
            };
            "com.apple.Terminal - Search man Page Index in Terminal - searchManPages" = {
              "enabled_context_menu" = 0;
              "enabled_services_menu" = 0;
              "presentation_modes" = {
                ContextMenu = 0;
                ServicesMenu = 0;
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
      systemPackages = [
        pkgs.custom.micswitch
        pkgs.custom.litra-rs
      ];
      # Hack: https://github.com/ghostty-org/ghostty/discussions/2832
      variables.XDG_DATA_DIRS = [ "$GHOSTTY_SHELL_INTEGRATION_XDG_DIR" ];
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

      # TODO: add autostart entries?
      casks = [
        "bitwarden"
        "arc"
        "battery"
        "obsidian"
        "macmediakeyforwarder"
        "spotify"
        "lulu"
        {
          name = "intellij-idea@eap";
          greedy = true;
        }
        "raycast"
        "jordanbaird-ice"
        "visual-studio-code"
        "istat-menus"
        "docker-desktop"
        "mullvad-vpn"
        "bettertouchtool"
        "karabiner-elements"
        "hammerspoon"
        "ghostty"
        "figma"
        "slack"
        "cameracontroller"
        "discord"
        {
          name = "ishare";
          greedy = true;
        }
      ];

      masApps = {
        Gifski = 1351639930;
      };
    };

    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
  };
}
