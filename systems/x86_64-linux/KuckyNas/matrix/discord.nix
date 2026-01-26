{
  config,
  lib,
  pkgs,
  ...
}:
let
  bridgeLib = import ./bridge.nix { inherit config lib; };
in
{
  services.custom.matrix-bridges.discord = bridgeLib.mkBridgeConfig {
    service = "discord";
    serviceName = "Discord";
    package = pkgs.mautrix-discord;
    commandPrefix = "!discord";
    botAvatar = "mxc://maunium.net/ygtkteZsXnGJLJHRchUwYWak";

    settings = {
      bridge = {
        private_chat_portal_meta = "always";

        backfill = {
          forward_limits = {
            initial = {
              dm = 500;
              channel = 500;
              thread = 500;
            };

            missed = {
              dm = 1500;
              channel = 1500;
              thread = 1500;
            };
          };

          max_guild_members = -1;
        };
      };

      database = { };
      appservice = {
        database = {
          type = "postgres";
          uri = "postgresql:///mautrix-discord?host=/run/postgresql";
          max_open_conns = 5;
          max_idle_conns = 1;
        };
      };
    };

    encryption = {
      require = null;
      appservice = null;
      msc4190 = null;
    };
  };
}
