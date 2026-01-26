{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    filterAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.custom.matrix-bridges;
  enabledBridges = filterAttrs (_: v: v.enable) cfg;
  bridgesWithManagedUsers = filterAttrs (_: v: v.createUser) enabledBridges;
  bridgesWithPostgres = filterAttrs (_: v: v.database.enable) enabledBridges;

  mkSystemdService =
    name: bridge:
    let
      dataDir = "/var/lib/mautrix-${name}";
      registrationFile = "${dataDir}/${name}-registration.yaml";
      settingsFile = "${dataDir}/config.yaml";
      settingsFormat = pkgs.formats.yaml { };
      settingsFileUnsubstituted = settingsFormat.generate "mautrix-${name}-config-unsubstituted.yaml" bridge.settings;
    in
    {
      description = "Mautrix-${name}, a Matrix-${bridge.serviceName} bridge";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "matrix-synapse.service"
        "matrix-bridges-registration.service"
      ]
      ++ lib.optionals bridge.database.enable [ "postgresql.service" ];
      requires = lib.optionals bridge.database.enable [ "postgresql.service" ];

      preStart = ''
        # Create data directory if it doesn't exist
        if [ ! -d "${dataDir}" ]; then
          mkdir -p ${dataDir}
          chown mautrix-${name}:mautrix-${name} ${dataDir}
          chmod 750 ${dataDir}
        fi

        # Generate config with environment variable substitutions
        umask 0177
        ${pkgs.envsubst}/bin/envsubst < ${settingsFileUnsubstituted} > ${settingsFile}
        chown mautrix-${name}:mautrix-${name} ${settingsFile}

        # Generate appservice registration if it doesn't exist
        if [ ! -f "${registrationFile}" ]; then
          ${bridge.package}/bin/${bridge.executable} \
            -c ${settingsFile} \
            -g -r ${registrationFile}
          chown mautrix-${name}:mautrix-${name} ${registrationFile}
          chmod 640 ${registrationFile}
        fi

        # Extract tokens from registration and update config
        if [ -f "${registrationFile}" ]; then
          AS_TOKEN=$(${pkgs.yq}/bin/yq -r '.as_token' ${registrationFile})
          HS_TOKEN=$(${pkgs.yq}/bin/yq -r '.hs_token' ${registrationFile})
          ${pkgs.yq}/bin/yq -y ".appservice.as_token = \"$AS_TOKEN\" | .appservice.hs_token = \"$HS_TOKEN\"" ${settingsFile} > ${settingsFile}.tmp
          mv ${settingsFile}.tmp ${settingsFile}
          chown mautrix-${name}:mautrix-${name} ${settingsFile}
          chmod 600 ${settingsFile}
        fi

        ${bridge.extraPreStart}
      '';

      serviceConfig = {
        Type = "simple";
        User = "mautrix-${name}";
        Group = "mautrix-${name}";
        WorkingDirectory = dataDir;
        EnvironmentFile = lib.mkIf (bridge.environmentFile != null) bridge.environmentFile;
        ExecStart = "${bridge.package}/bin/${bridge.executable} -c ${settingsFile}";
        Restart = "on-failure";
        RestartSec = "30s";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ dataDir ];
        ReadOnlyPaths = [ "/run/secrets" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
      };
    };
in
{
  options.services.custom.matrix-bridges = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkEnableOption "Matrix bridge for ${name}";

            serviceName = mkOption {
              type = types.str;
              default = name;
              description = "Human-readable service name (e.g., 'Signal', 'Discord')";
            };

            package = mkOption {
              type = types.package;
              description = "The bridge package to use";
            };

            executable = mkOption {
              type = types.str;
              default = "mautrix-${name}";
              description = "Name of the executable in the package";
            };

            port = mkOption {
              type = types.port;
              description = "Port the bridge listens on";
            };

            settings = mkOption {
              type = types.attrs;
              description = "Bridge configuration (will be converted to YAML)";
            };

            environmentFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Path to environment file for secrets";
            };

            extraPreStart = mkOption {
              type = types.lines;
              default = "";
              description = "Extra commands to run in the preStart script";
            };

            createUser = mkOption {
              type = types.bool;
              default = true;
              description = "Whether to create a system user for this bridge";
            };

            database = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to create a PostgreSQL database for this bridge";
              };

              name = mkOption {
                type = types.str;
                default = "mautrix-${name}";
                description = "Name of the PostgreSQL database";
              };

              user = mkOption {
                type = types.str;
                default = "mautrix-${name}";
                description = "PostgreSQL user for the bridge";
              };
            };
          };
        }
      )
    );
    default = { };
  };

  config = mkIf (enabledBridges != { }) {
    # Create users and groups for bridges
    users = {
      users =
        (mapAttrs' (name: _: {
          name = "mautrix-${name}";
          value = {
            isSystemUser = true;
            group = "mautrix-${name}";
            home = "/var/lib/mautrix-${name}";
            description = "Mautrix-${name} bridge user";
          };
        }) bridgesWithManagedUsers)
        // {
          # Add matrix-synapse user to all bridge groups so it can read registration files
          matrix-synapse.extraGroups = lib.mapAttrsToList (name: _: "mautrix-${name}") enabledBridges;
        };

      groups = mapAttrs' (name: _: {
        name = "mautrix-${name}";
        value = { };
      }) bridgesWithManagedUsers;
    };

    # Setup PostgreSQL databases
    services.postgresql = mkIf (bridgesWithPostgres != { }) {
      ensureDatabases = lib.mapAttrsToList (_: bridge: bridge.database.name) bridgesWithPostgres;
      ensureUsers = lib.mapAttrsToList (_: bridge: {
        name = bridge.database.user;
        ensureDBOwnership = true;
      }) bridgesWithPostgres;
    };

    # Create systemd services (both registration and bridge services)
    systemd.services = {
      # Registration service that runs before Synapse
      matrix-bridges-registration = {
        description = "Generate Matrix bridge registration files";
        wantedBy = [ "matrix-synapse.service" ];
        before = [ "matrix-synapse.service" ];
        after = lib.optionals (bridgesWithPostgres != { }) [ "postgresql.service" ];
        wants = lib.optionals (bridgesWithPostgres != { }) [ "postgresql.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ReadOnlyPaths = [ "/run/secrets" ];
        };

        script = lib.concatStringsSep "\n\n" (
          lib.mapAttrsToList (
            name: bridge:
            let
              dataDir = "/var/lib/mautrix-${name}";
              registrationFile = "${dataDir}/${name}-registration.yaml";
              settingsFile = "${dataDir}/config.yaml";
              settingsFormat = pkgs.formats.yaml { };
              settingsFileUnsubstituted = settingsFormat.generate "mautrix-${name}-config-unsubstituted.yaml" bridge.settings;
            in
            ''
              echo "Generating registration for ${name}..."

              # Create data directory with proper permissions
              mkdir -p ${dataDir}
              chown mautrix-${name}:mautrix-${name} ${dataDir}
              chmod 750 ${dataDir}

              # Source environment file if it exists
              ${lib.optionalString (bridge.environmentFile != null) ''
                if [ -f "${bridge.environmentFile}" ]; then
                  set -a
                  source "${bridge.environmentFile}"
                  set +a
                fi
              ''}

              # Generate config with environment variable substitutions
              ${pkgs.envsubst}/bin/envsubst < ${settingsFileUnsubstituted} > ${settingsFile}
              chown mautrix-${name}:mautrix-${name} ${settingsFile}
              chmod 600 ${settingsFile}

              # Generate appservice registration if it doesn't exist
              if [ ! -f "${registrationFile}" ]; then
                ${bridge.package}/bin/${bridge.executable} \
                  -c ${settingsFile} \
                  -g -r ${registrationFile}
                chown mautrix-${name}:mautrix-${name} ${registrationFile}
                chmod 640 ${registrationFile}

                # Extract tokens from registration and update config
                AS_TOKEN=$(${pkgs.yq}/bin/yq -r '.as_token' ${registrationFile})
                HS_TOKEN=$(${pkgs.yq}/bin/yq -r '.hs_token' ${registrationFile})
                ${pkgs.yq}/bin/yq -y ".appservice.as_token = \"$AS_TOKEN\" | .appservice.hs_token = \"$HS_TOKEN\"" ${settingsFile} > ${settingsFile}.tmp
                mv ${settingsFile}.tmp ${settingsFile}
                chown mautrix-${name}:mautrix-${name} ${settingsFile}
                chmod 600 ${settingsFile}
              fi

              echo "Registration for ${name} complete."
            ''
          ) enabledBridges
        );
      };
    }
    // (mapAttrs' (name: bridge: {
      name = "mautrix-${name}";
      value = mkSystemdService name bridge;
    }) enabledBridges);

    # Update Synapse configuration to include bridge registration files
    services.matrix-synapse.settings.app_service_config_files = lib.mkBefore (
      lib.mapAttrsToList (name: _: "/var/lib/mautrix-${name}/${name}-registration.yaml") enabledBridges
    );
  };
}
