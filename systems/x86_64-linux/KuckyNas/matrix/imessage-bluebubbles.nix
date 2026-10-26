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
  # The BlueBubbles server URL and password aren't configured here: they're
  # given to the bridge bot once with `!im login`.
  services.custom.matrix-bridges.imessage = bridgeLib.mkBridgeConfig {
    service = "imessage";
    serviceName = "iMessage";
    package = pkgs.custom.mautrix-imessage;
    commandPrefix = "!im";
    botAvatar = "mxc://maunium.net/tManJEpANASZvDVzvRvhILdX";

    settings = {
      network = {
        displayname_template = "{{or .Name .Address}}";
        initial_chat_sync_count = 25;
        contact_refresh_interval = "1h";
      };

      bridge = {
        async_events = false;
        split_portals = false;
        resend_bridge_info = false;
        no_bridge_info_state_key = false;
        bridge_status_notices = "errors";
        unknown_error_auto_reconnect = null;
        bridge_matrix_leave = false;
        bridge_notices = false;
        tag_only_on_create = true;
        only_bridge_tags = [
          "m.favourite"
          "m.lowpriority"
        ];
        mute_only_on_create = true;
        deduplicate_matrix_messages = false;
        cross_room_replies = false;
        revert_failed_state_changes = false;
        kick_matrix_users = true;
        cleanup_on_logout.enabled = false;
      };

      database = {
        max_conn_idle_time = null;
        max_conn_lifetime = null;
      };

      homeserver = {
        status_endpoint = null;
        message_send_checkpoint_endpoint = null;
        websocket = false;
        ping_interval_seconds = 0;
      };

      appservice = {
        public_address = null;
        async_transactions = false;
      };

      matrix = {
        upload_file_threshold = 5242880;
      };

      analytics = {
        token = null;
      };

      provisioning = {
        allow_matrix_auth = false;
        debug_endpoints = false;
        enable_session_transfers = false;
      };

      public_media = {
        enabled = false;
      };

      direct_media = {
        enabled = false;
      };
    };

    encryption = {
      allow_key_sharing = true;
    };
  };
}
