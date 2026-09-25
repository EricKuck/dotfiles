{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;
  darwinCfg = config.gha-runner.irl.darwin;
  xcodeCfg = darwinCfg.xcode;

  buildToolsVersion = "37.0.0";

  emptySysImgXml = pkgs.writeText "sys-img2-3.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <sys-img:sdk-sys-img xmlns:sys-img="http://schemas.android.com/sdk/android/repo/sys-img2/03"/>
  '';
  emptyAddonXml = pkgs.writeText "addon2-3.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <addon:sdk-addon xmlns:addon="http://schemas.android.com/sdk/android/repo/addon2/03"/>
  '';

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    repoXmls = {
      packages = [ ./android-repo/repository2-3.xml ];
      images = [ emptySysImgXml ];
      addons = [ emptyAddonXml ];
    };
    buildToolsVersions = [ buildToolsVersion ];
    platformVersions = [
      "37.0"
      "37.2"
    ];
    platformToolsVersion = "37.0.1";
    cmakeVersions = [ "3.22.1" ];
    includeNDK = true;
    ndkVersions = [ "28.2.13676358" ];
  };
  androidHome = "${androidComposition.androidsdk}/libexec/android-sdk";

  extraPackages = with pkgs; [
    git-lfs
    zulu21
    zulu25
    firebase-tools
    python3
    gawk
    jq
    curl
    unzip
    openssl
    ninja
    gn
    svgo
    fd
    ripgrep
    perl
    gnugrep
    gnused
    findutils
    fastlane
    ffmpeg
    libwebp
    nodejs_26
  ];

  environment = {
    ANDROID_HOME = androidHome;
    ANDROID_SDK_ROOT = androidHome;
    JAVA_HOME = "${pkgs.zulu25}";
    GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidHome}/build-tools/${buildToolsVersion}/aapt2";
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
  };

  darwinSystemTools = pkgs.runCommand "darwin-system-tools" { } ''
    mkdir -p $out/bin
    for tool in sysctl sw_vers arch system_profiler; do
      for src in /usr/sbin/$tool /usr/bin/$tool; do
        if [ -e "$src" ]; then
          ln -s "$src" "$out/bin/$tool"
          break
        fi
      done
    done
  '';

  # All runners share one user and HOME, so caches, keychains and logins are
  # shared. Each runner still keeps its own RUNNER_ROOT under the home.
  runnerUser = "_gha-runner";
  runnerGroup = "_gha-runner";
  runnerHome = "/var/lib/github-runners";

  # Default keychain for the runner user, so Xcode can install signing
  # certificates. Empty password: it only guards against users other than the
  # runner user, which every job already runs as.
  runnerKeychain = "${runnerHome}/Library/Keychains/runner.keychain-db";
  runAsRunner = "/usr/bin/sudo -u ${runnerUser} -H";

  # Intermediate that issues current Apple Development/Distribution certs.
  # Without it codesign can't build the chain ("unable to build chain to
  # self-signed root") and fails with errSecInternalComponent.
  wwdrG3 = pkgs.fetchurl {
    url = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer";
    hash = "sha256-3PIYeMd/QZjktGFPA9aW2JxmxmAI1CROG5kWGqyRYB8=";
  };

  gradleProperties = {
    "org.gradle.java.installations.paths" = "${pkgs.zulu21},${pkgs.zulu25}";
    "org.gradle.java.home" = "${pkgs.zulu25}";
  };

  simulatorSdks = {
    iOS = "iphonesimulator";
    watchOS = "watchsimulator";
    tvOS = "appletvsimulator";
    visionOS = "xrsimulator";
  };

  xcodesPath = "${config.homebrew.prefix}/bin/xcodes";
  xcodesUser = config.system.primaryUser;

  xcodeAppPath = "${xcodeCfg.directory}/Xcode-${xcodeCfg.version}.app";
  xcodeDeveloperDir = "${xcodeAppPath}/Contents/Developer";
  xcodeBuildPath = "${xcodeDeveloperDir}/usr/bin/xcodebuild";
  xcodesInstallCommand = ''
    /bin/launchctl asuser "$(/usr/bin/id -u ${lib.escapeShellArg xcodesUser})" \
      /usr/bin/sudo -u ${lib.escapeShellArg xcodesUser} --set-home \
      --preserve-env=XCODES_USERNAME,XCODES_PASSWORD,FASTLANE_SESSION \
      ${lib.escapeShellArg xcodesPath} install ${lib.escapeShellArg xcodeCfg.version} \
      --directory ${lib.escapeShellArg xcodeCfg.directory} \
      --empty-trash \
      --experimental-unxip \
      --no-superuser \
      ${lib.optionalString (xcodeCfg.fastlaneSessionFile != null) "--use-fastlane-auth"}
  '';

  xcodeRunnerTools = pkgs.runCommandLocal "gha-runner-xcode-tools" { } ''
        mkdir -p $out/bin

        for tool in xcrun simctl actool ibtool xctrace; do
          cat > "$out/bin/$tool" <<EOF
    #!${pkgs.bash}/bin/bash
    export DEVELOPER_DIR=${lib.escapeShellArg xcodeDeveloperDir}
    exec ${lib.escapeShellArg "${xcodeDeveloperDir}/usr/bin/$tool"} "\$@"
    EOF
          chmod +x "$out/bin/$tool"
        done

        # Each runner has its own security session (SessionCreate), where the
        # keychain starts locked, so unlock it before Xcode needs to sign.
        cat > "$out/bin/xcodebuild" <<EOF
    #!${pkgs.bash}/bin/bash
    export DEVELOPER_DIR=${lib.escapeShellArg xcodeDeveloperDir}
    /usr/bin/security unlock-keychain -p "" ${lib.escapeShellArg runnerKeychain} >/dev/null 2>&1 || true
    exec ${lib.escapeShellArg "${xcodeDeveloperDir}/usr/bin/xcodebuild"} "\$@"
    EOF
        chmod +x "$out/bin/xcodebuild"

        cat > "$out/bin/xcode-select" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec /usr/bin/xcode-select "$@"
    EOF
        chmod +x "$out/bin/xcode-select"
  '';
in
{
  options.gha-runner.irl.runners = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.tokenFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to file containing the runner's registration token.";
        };
      }
    );
    default = { };
    description = "Infinite-Retry GitHub Actions runners, keyed by runner name.";
  };

  options.gha-runner.irl.darwin = {
    uid = lib.mkOption {
      type = lib.types.int;
      default = 540;
      description = "UID of the shared runner user, also used as the GID of its group.";
    };

    xcode = {
      version = lib.mkOption {
        type = lib.types.str;
        default = "27.0.0";
        description = "Xcode version to keep installed for Darwin GitHub Actions runners.";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "/Applications";
        description = "Directory where xcodes installs Xcode.";
      };

      simulatorPlatforms = lib.mkOption {
        type = lib.types.listOf (lib.types.enum (lib.attrNames simulatorSdks));
        default = [ "iOS" ];
        description = ''
          Simulator runtimes to download for the selected Xcode. Xcode no longer
          bundles these, and they're needed for simulator builds and tests.
        '';
      };

      usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File containing the Apple ID username for xcodes.
          Only needed when the requested Xcode is not already installed and xcodes
          has not already been authenticated via the system keychain.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File containing the Apple ID password for xcodes.
          Only needed when the requested Xcode is not already installed and xcodes
          has not already been authenticated via the system keychain.
        '';
      };

      fastlaneSessionFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File containing a FASTLANE_SESSION value for non-interactive xcodes
          installs. When set, the activation hook installs Xcode with
          `xcodes --use-fastlane-auth`.

          If no credentials are configured and activation is run from a
          terminal, xcodes prompts for the Apple ID, password and 2FA code.
        '';
      };
    };
  };

  config = lib.mkIf (cfg != { }) {
    assertions = [
      {
        assertion = config.homebrew.enable;
        message = "gha-runner.irl darwin runners require homebrew.enable, since xcodes is installed via Homebrew.";
      }
      {
        assertion = xcodesUser != null;
        message = "gha-runner.irl darwin runners require system.primaryUser, whose keychain xcodes uses to sign in to Apple.";
      }
    ];

    homebrew.brews = [ "xcodes" ];

    users = {
      knownUsers = [ runnerUser ];
      knownGroups = [ runnerGroup ];

      groups.${runnerGroup} = {
        gid = darwinCfg.uid;
        description = "GitHub Actions runners";
      };

      users.${runnerUser} = {
        uid = darwinCfg.uid;
        gid = darwinCfg.uid;
        home = runnerHome;
        createHome = false;
        shell = "/bin/bash";
        isHidden = true;
        description = "GitHub Actions runners";
      };
    };

    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "gha-runner-${name}-token" {
        owner = runnerUser;
      }
    ) cfg;

    services.github-runners = lib.mapAttrs (name: runner: {
      enable = true;
      inherit name;
      url = "https://github.com/Infinite-Retry";
      tokenFile = toString runner.tokenFile;
      replace = true;
      extraLabels = [ "macOS" ];
      user = runnerUser;
      group = runnerGroup;
      extraPackages = extraPackages ++ [
        androidComposition.androidsdk
        darwinSystemTools
        xcodeRunnerTools
      ];
      extraEnvironment = environment // {
        HOME = runnerHome;
        DEVELOPER_DIR = xcodeDeveloperDir;
        XCODE_APP_PATH = xcodeAppPath;
        XCODE_DEVELOPER_DIR = xcodeDeveloperDir;
      };
      serviceOverrides.SessionCreate = true;
    }) cfg;

    # nix-darwin only chowns the top-level runner dirs, so files left behind by a
    # previous runner user (e.g. .runner/.credentials, logs, caches) would be
    # unreadable. The home also holds every runner's state and work dir. Only
    # recurse when the top-level owner is wrong, since the caches get large.
    # Runs right after users are created, before launchd starts the runners and
    # before nix-darwin chowns the top-level dirs itself.
    system.activationScripts.users.text = lib.mkAfter ''
      mkdir -p ${runnerHome}
      for dir in ${runnerHome} ${
        lib.concatMapStringsSep " " (name: "/var/log/github-runners/${name}") (lib.attrNames cfg)
      }; do
        if [ -d "$dir" ] && [ "$(/usr/bin/stat -f %Su "$dir")" != ${runnerUser} ]; then
          echo >&2 "fixing ownership of $dir..."
          chown -R ${runnerUser}:${runnerGroup} "$dir"
        fi
      done
    '';

    system.activationScripts.postActivation.text = ''
      mkdir -p ${runnerHome}/.gradle
      cat > ${runnerHome}/.gradle/gradle.properties <<'GRADLE_EOF'
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") gradleProperties)}
      GRADLE_EOF
      chmod 644 ${runnerHome}/.gradle/gradle.properties
      chown -R ${runnerUser}:${runnerGroup} ${runnerHome}/.gradle

      /usr/sbin/dseditgroup -o checkmember -m ${runnerUser} _developer >/dev/null \
        || /usr/sbin/dseditgroup -o edit -a ${runnerUser} -t user _developer

      # Fails harmlessly when the certificate is already installed
      /usr/bin/security add-certificates -k /Library/Keychains/System.keychain ${wwdrG3} 2>/dev/null || true

      if [ ! -f ${runnerKeychain} ]; then
        echo >&2 "creating runner keychain..."
        ${runAsRunner} mkdir -p ${dirOf runnerKeychain}
        ${runAsRunner} /usr/bin/security create-keychain -p "" ${runnerKeychain}
      fi
      ${runAsRunner} /usr/bin/security unlock-keychain -p "" ${runnerKeychain}
      # No auto-lock timeout or lock on sleep
      ${runAsRunner} /usr/bin/security set-keychain-settings ${runnerKeychain}
      # Keep System.keychain searchable for intermediates like WWDR G3
      ${runAsRunner} /usr/bin/security list-keychains -d user -s ${runnerKeychain} /Library/Keychains/System.keychain
      ${runAsRunner} /usr/bin/security default-keychain -d user -s ${runnerKeychain}

      /usr/sbin/DevToolsSecurity -enable >/dev/null

      if [ ! -d ${lib.escapeShellArg xcodeAppPath} ]; then
        export PATH=${lib.escapeShellArg "${lib.makeBinPath [ pkgs.coreutils ]}:/usr/bin:/bin:/usr/sbin:/sbin"}

        echo >&2 "installing Xcode ${xcodeCfg.version}..."

        ${
          if xcodeCfg.fastlaneSessionFile != null then
            ''
              FASTLANE_SESSION="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.fastlaneSessionFile)})"
              export FASTLANE_SESSION
              ${xcodesInstallCommand}
            ''
          else if xcodeCfg.usernameFile != null && xcodeCfg.passwordFile != null then
            ''
              XCODES_USERNAME="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.usernameFile)})"
              export XCODES_USERNAME
              XCODES_PASSWORD="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.passwordFile)})"
              export XCODES_PASSWORD
              ${xcodesInstallCommand}
            ''
          else
            ''
              if [ -t 0 ]; then
                echo >&2 "No xcodes credentials configured; xcodes will prompt for an Apple ID."
                ${xcodesInstallCommand}
              else
                echo >&2 "Xcode ${xcodeCfg.version} is missing at ${xcodeAppPath} and no xcodes credentials are configured."
                echo >&2 "Run activation from a terminal to sign in interactively, configure gha-runner.irl.darwin.xcode.fastlaneSessionFile or both usernameFile and passwordFile, or pre-install Xcode ${xcodeCfg.version}."
                exit 1
              fi
            ''
        }
      fi

      /usr/bin/xcode-select --switch ${lib.escapeShellArg xcodeDeveloperDir}

      if ! ${lib.escapeShellArg xcodeBuildPath} -checkFirstLaunchStatus >/dev/null 2>&1; then
        ${lib.escapeShellArg xcodeBuildPath} -runFirstLaunch
      fi

      ${lib.concatMapStrings (platform: ''
        sdkVersion="$(DEVELOPER_DIR=${lib.escapeShellArg xcodeDeveloperDir} /usr/bin/xcrun --sdk ${simulatorSdks.${platform}} --show-sdk-version)"
        if ! DEVELOPER_DIR=${lib.escapeShellArg xcodeDeveloperDir} /usr/bin/xcrun simctl list runtimes | grep -q "^${platform} $sdkVersion"; then
          echo >&2 "installing ${platform} $sdkVersion simulator runtime..."
          ${lib.escapeShellArg xcodeBuildPath} -downloadPlatform ${platform}
        fi
      '') xcodeCfg.simulatorPlatforms}
    '';
  };
}
