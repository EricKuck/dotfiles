{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    filterAttrs
    mapAttrs
    mapAttrs'
    mkEnableOption
    mkOption
    optional
    optionalAttrs
    types
    ;
  cfg = config.services.custom.gha-runner;
  enabledRunners = filterAttrs (_: runner: runner.enable) cfg.runners;
in
{
  options.services.custom.gha-runner.runners = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkEnableOption "GitHub Actions runner ${name}" // {
              default = true;
            };

            url = mkOption {
              type = types.str;
              description = "GitHub repository or organization URL to register against.";
            };

            extraGroups = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional groups for the runner user.";
            };

            extraPackages = mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Packages available to the runner.";
            };

            androidPackages = mkOption {
              type = types.nullOr types.attrs;
              default = null;
              description = "Result of pkgs.androidenv.composeAndroidPackages for this runner (adds SDK to PATH and sets ANDROID_HOME/ANDROID_SDK_ROOT).";
            };

            environment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Environment variables for the runner service.";
            };

            description = mkOption {
              type = types.str;
              default = "GitHub Actions runner ${name}";
              description = "Description for the runner user.";
            };

            gradleProperties = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "gradle.properties contents as an attrset written to the runner's home.";
            };
          };
        }
      )
    );
    default = { };
    description = "GitHub Actions runners to provision.";
  };

  config = {
    sops.secrets = mapAttrs' (name: runner: {
      name = "gha-runner-${name}-token";
      value = {
        owner = "gha-runner-${name}";
      };
    }) enabledRunners;

    users = {
      users = mapAttrs' (name: runner: {
        name = "gha-runner-${name}";
        value = {
          group = "gha-runner";
          extraGroups = runner.extraGroups;
          description = runner.description;
          isNormalUser = true;
          linger = true;
        };
      }) enabledRunners;

      groups = {
        "gha-runner" = { };
      };
    };

    systemd.services = mapAttrs' (
      name: runner:
      let
        android = runner.androidPackages;
        androidHome = if android != null then "${android.androidsdk}/libexec/android-sdk" else null;
      in
      {
        name = "github-runner-${name}";
        value = {
          serviceConfig.ProtectHome = lib.mkForce false;
          environment =
            runner.environment
            // optionalAttrs (android != null) {
              ANDROID_HOME = androidHome;
              ANDROID_SDK_ROOT = androidHome;
            };
        };
      }
    ) enabledRunners;

    systemd.tmpfiles.rules =
      let
        mkGradleRules =
          name: runner:
          let
            props = runner.gradleProperties;
          in
          if props == { } then
            [ ]
          else
            let
              gradleDir = "/home/gha-runner-${name}/.gradle";
              gradleFile = pkgs.writeText "gha-runner-${name}-gradle.properties" (
                lib.generators.toKeyValue { } props + "\n"
              );
            in
            [
              "d ${gradleDir} 0750 gha-runner-${name} gha-runner - -"
              "L ${gradleDir}/gradle.properties - - - - ${gradleFile}"
            ];
      in
      lib.flatten (lib.mapAttrsToList mkGradleRules enabledRunners);

    services.github-runners = mapAttrs (name: runner: {
      enable = true;
      inherit (runner) url;
      extraPackages =
        runner.extraPackages ++ optional (runner.androidPackages != null) runner.androidPackages.androidsdk;
      name = name;
      user = "gha-runner-${name}";
      group = "gha-runner";
      tokenFile = config.sops.secrets."gha-runner-${name}-token".path;
    }) enabledRunners;
  };
}
