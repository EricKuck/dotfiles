{
  config,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/matrix-authentication-service";
  configFile = "${dataDir}/config.yaml";
  settingsFormat = pkgs.formats.yaml { };

  settings = {
    http = {
      listeners = [
        {
          name = "web";
          resources = [
            { name = "discovery"; }
            { name = "human"; }
            { name = "oauth"; }
            { name = "compat"; }
            { name = "graphql"; }
            {
              name = "assets";
              path = "${pkgs.matrix-authentication-service}/share/matrix-authentication-service/assets/";
            }
          ];
          binds = [
            {
              host = "127.0.0.1";
              port = config.ports.matrix-mas;
            }
          ];
        }
      ];

      public_base = "https://mas.kuck.ing";
      issuer = "https://mas.kuck.ing";
    };

    database = {
      uri = "postgresql:///matrix-mas?host=/run/postgresql&user=matrix-mas";
    };

    clients = [
      {
        client_id = "0000000000000000000SYNAPSE";
        client_auth_method = "client_secret_basic";
        client_secret = "$MAS_SYNAPSE_CLIENT_SECRET";
      }
    ];

    matrix = {
      kind = "synapse";
      homeserver = "kuck.ing";
      endpoint = "http://localhost:${toString config.ports.matrix-synapse}";
      secret = "$SYNAPSE_MAS_ADMIN_TOKEN";
    };

    passwords = {
      enabled = true;
      schemes = [
        {
          version = 1;
          algorithm = "argon2id";
        }
      ];
    };

    account = {
      password_registration_enabled = true;
      email_change_allowed = true;
      displayname_change_allowed = true;
      password_change_allowed = true;
    };

    email = {
      from = "\"Matrix\" <$MAS_SMTP_ADDRESS>";
      reply_to = "\"Matrix\" <$MAS_SMTP_ADDRESS>";
      transport = "smtp";
      mode = "tls";
      hostname = "$MAS_SMTP_HOSTNAME";
      port = 587;
      username = "$MAS_SMTP_USERNAME";
      password = "$MAS_SMTP_PASSWORD";
    };

    experimental = {
      access_token_ttl = 300;
      compat_token_ttl = 300;
    };
  };

  settingsFileUnsubstituted = settingsFormat.generate "mas-config-unsubstituted.yaml" settings;

in
{
  environment.systemPackages = with pkgs; [
    matrix-authentication-service
  ];

  users.users.matrix-mas = {
    isSystemUser = true;
    group = "matrix-mas";
    home = dataDir;
    description = "Matrix Authentication Service user";
  };

  users.groups.matrix-mas = { };

  sops.secrets = {
    matrix-mas-config = {
      owner = "matrix-mas";
      group = "matrix-mas";
      mode = "0440";
      restartUnits = [ "matrix-authentication-service.service" ];
    };

    matrix-mas-signing-key = {
      owner = "matrix-mas";
      group = "matrix-mas";
      mode = "0440";
      restartUnits = [ "matrix-authentication-service.service" ];
    };

    matrix-mas-encryption-key = {
      owner = "matrix-mas";
      group = "matrix-mas";
      mode = "0440";
      restartUnits = [ "matrix-authentication-service.service" ];
    };
  };

  systemd.services.matrix-authentication-service = {
    description = "Matrix Authentication Service";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    requires = [ "postgresql.service" ];

    preStart = ''
            set -a
            source ${config.sops.secrets.matrix-mas-config.path}
            set +a

            umask 0177
            ${pkgs.envsubst}/bin/envsubst \
              -i ${settingsFileUnsubstituted} \
              -o ${configFile}

            cat >> ${configFile} <<EOF
      secrets:
        encryption_file: ${config.sops.secrets.matrix-mas-encryption-key.path}
        keys:
          - kid: default
            key_file: ${config.sops.secrets.matrix-mas-signing-key.path}
      EOF

            chown matrix-mas:matrix-mas ${configFile}

            ${pkgs.matrix-authentication-service}/bin/mas-cli database migrate \
              --config ${configFile}
    '';

    serviceConfig = {
      Type = "simple";
      User = "matrix-mas";
      Group = "matrix-mas";
      StateDirectory = "matrix-authentication-service";
      StateDirectoryMode = "0750";
      WorkingDirectory = dataDir;
      EnvironmentFile = config.sops.secrets.matrix-mas-config.path;
      ExecStart = "${pkgs.matrix-authentication-service}/bin/mas-cli server --config ${configFile}";
      Restart = "on-failure";
      RestartSec = "30s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
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

  services.caddy-with-blackbox.virtualHosts."mas.kuck.ing" = {
    extraConfig = ''
      import tls

      # Handle requests from matrix.kuck.ing
      @from_matrix header Origin https://matrix.kuck.ing
      handle @from_matrix {
        reverse_proxy http://localhost:${toString config.ports.matrix-mas} {
          header_down >Access-Control-Allow-Origin "https://matrix.kuck.ing"
        }
      }

      # Everything else gets wildcard
      handle {
        reverse_proxy http://localhost:${toString config.ports.matrix-mas}
      }
    '';
  };
}
