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
  services.custom.matrix-bridges.slack = bridgeLib.mkBridgeConfig {
    service = "slack";
    serviceName = "Slack";
    package = pkgs.mautrix-slack;
    commandPrefix = "!slack";
    botAvatar = "mxc://maunium.net/TdemSetLinesAHcYjEaUZ";

    settings = {
      network = {
        workspace_avatar_in_rooms = true;
        participant_sync_count = 30;

        backfill = {
          conversation_count = -1;
        };
      };
    };
  };
}
