{
  config,
  pkgs,
  ...
}:
let
  synapse-admin = pkgs.synapse-admin-etkecc.withConfig {
    restrictBaseUrl = [
      "https://matrix.kuck.ing"
    ];
  };
in
{
  environment.systemPackages = with pkgs; [
    synadm
  ];

  services = {
    matrix-synapse = {
      enable = true;

      extras = [ "oidc" ];

      settings = {
        server_name = "kuck.ing";
        public_baseurl = "https://matrix.kuck.ing";

        suppress_key_server_warning = true;

        rc_message = {
          per_second = 1000;
          burst_count = 10000;
        };

        rc_login = {
          address = {
            per_second = 5;
            burst_count = 50;
          };

          account = {
            per_second = 5;
            burst_count = 50;
          };
        };

        auto_accept_invites = {
          enabled = false;
        };

        listeners = [
          {
            port = config.ports.matrix-synapse;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = [
                  "client"
                  "federation"
                ];
                compress = true;
              }
            ];
          }
        ];

        database = {
          name = "psycopg2";
          args = {
            database = "matrix-synapse";
            user = "matrix-synapse";
            host = "/run/postgresql";
            cp_min = 5;
            cp_max = 10;
          };
        };

        matrix_authentication_service = {
          enabled = true;
          endpoint = "http://localhost:${toString config.ports.matrix-mas}";
        };

        max_upload_size = "100M";
        url_preview_enabled = true;
        url_preview_ip_range_blacklist = [
          "127.0.0.0/8"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "100.64.0.0/10"
          "169.254.0.0/16"
          "::1/128"
          "fe80::/64"
          "fc00::/7"
        ];

        enable_metrics = true;
        report_stats = false;

        macaroon_secret_key = "$SYNAPSE_MACAROON_SECRET";

        log_config = pkgs.writeText "synapse-log-config.yaml" ''
          version: 1
          formatters:
            precise:
              format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
          handlers:
            console:
              class: logging.StreamHandler
              formatter: precise
          loggers:
            synapse:
              level: INFO
            synapse.storage.SQL:
              level: INFO
          root:
            level: INFO
            handlers: [console]
        '';
      };

      extraConfigFiles = [
        config.sops.secrets.matrix-synapse-config.path
      ];
    };
  };

  sops.secrets = {
    matrix-synapse-config = {
      owner = "matrix-synapse";
      group = "matrix-synapse";
      mode = "0440";
      restartUnits = [ "matrix-synapse.service" ];
    };
  };

  services.caddy-with-blackbox.virtualHosts = {
    "matrix.kuck.ing" = {
      extraConfig = ''
        import tls

        # Serve synapse-admin at /admin
        handle /admin* {
          uri strip_prefix /admin
          root * ${synapse-admin}
          try_files {path} {path}/ /index.html
          file_server
        }

        # Serve synapse-admin assets (referenced as /assets/... by the app)
        handle /assets/* {
          root * ${synapse-admin}
          file_server
        }

        # Serve config.json for synapse-admin
        handle /config.json {
          root * ${synapse-admin}
          file_server
        }

        # Proxy MAS compat endpoints to MAS (including all sub-paths)
        @mas_login path_regexp ^/_matrix/client/(r0|v3|unstable)/login(/.*)?$
        handle @mas_login {
          reverse_proxy http://localhost:${toString config.ports.matrix-mas}
        }

        @mas_logout path_regexp ^/_matrix/client/(r0|v3|unstable)/logout(/.*)?$
        handle @mas_logout {
          reverse_proxy http://localhost:${toString config.ports.matrix-mas}
        }

        @mas_refresh path_regexp ^/_matrix/client/(r0|v3|unstable)/refresh(/.*)?$
        handle @mas_refresh {
          reverse_proxy http://localhost:${toString config.ports.matrix-mas}
        }

        # Everything else goes to Synapse
        handle {
          reverse_proxy http://localhost:${toString config.ports.matrix-synapse}
        }
      '';
    };
  };
}
