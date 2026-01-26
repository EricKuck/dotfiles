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
  services.custom.matrix-bridges.signal = bridgeLib.mkBridgeConfig {
    service = "signal";
    serviceName = "Signal";
    package = pkgs.mautrix-signal;
    commandPrefix = "!signal";
    botAvatar = "mxc://maunium.net/wPJgTQbZOtpBFmDNkiNEMDUp";

    settings = {
      network = {
        displayname_template = "{{or .ProfileName .PhoneNumber \"Unknown user\"}}";
        use_contact_avatars = true;
        sync_contacts_on_startup = true;
        use_outdated_profiles = false;
        number_in_topic = true;
        device_name = "mautrix-signal";
        note_to_self_avatar = "mxc://maunium.net/REBIVrqjZwmaWpssCZpBlmlL";
        location_format = "https://www.google.com/maps/place/%[1]s,%[2]s";
        disappear_view_once = false;
        extev_polls = false;
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
