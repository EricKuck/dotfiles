{ config, lib, ... }:

{
  mkBridgeConfig =
    {
      service,
      serviceName,
      package,
      commandPrefix,
      botAvatar,
      settings ? { },
      encryption ? { },
    }:
    {
      enable = true;
      inherit serviceName package;
      port = config.ports."matrix-${service}";
      environmentFile = config.sops.templates."mautrix-${service}-env".path;

      settings = lib.recursiveUpdate {
        bridge = {
          command_prefix = commandPrefix;
          personal_filtering_spaces = true;
          private_chat_portal_meta = true;
          relay.enabled = false;
          permissions = {
            "*" = "relay";
            "kuck.ing" = "user";
          };
        };

        database = {
          type = "postgres";
          uri = "postgresql:///mautrix-${service}?host=/run/postgresql";
          max_open_conns = 5;
          max_idle_conns = 1;
        };

        homeserver = {
          address = "http://localhost:${toString config.ports.matrix-synapse}";
          domain = "kuck.ing";
          software = "standard";
          async_media = false;
        };

        appservice = {
          address = "http://localhost:${toString config.ports."matrix-${service}"}";
          hostname = "127.0.0.1";
          port = config.ports."matrix-${service}";
          id = service;
          bot = {
            username = "${service}bot";
            displayname = "${serviceName} bridge bot";
            avatar = botAvatar;
          };
          ephemeral_events = true;
          username_template = "${service}_{{.}}";
        };

        matrix = {
          message_status_events = false;
          delivery_receipts = false;
          message_error_notices = true;
          sync_direct_chat_list = true;
          federate_rooms = true;
        };

        provisioning = {
          shared_secret = "generate";
        };

        encryption = lib.recursiveUpdate {
          allow = true;
          default = true;
          require = false;
          appservice = false;
          msc4190 = true;
          pickle_key = "$MAUTRIX_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] service)}_PICKLE_KEY";
        } encryption;

        double_puppet = {
          secrets = {
            "kuck.ing" = "$DOUBLEPUPPET_TOKEN";
          };
        };

        backfill = {
          enabled = true;
        };

        logging = {
          min_level = "info";
          writers = [
            {
              type = "stdout";
              format = "pretty-colored";
            }
          ];
        };
      } settings;
    };
}
