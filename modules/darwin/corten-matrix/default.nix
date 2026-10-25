{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkDefault
    mkPackageOption
    types
    ;

  cfg = config.custom.services.corten-matrix;

  # Same label the upstream installer uses, so `corten-matrix start / stop /
  # restart / status / logs` drive this agent instead of looking for their own.
  label = "com.lrhodin.corten-matrix";

  settingsFormat = pkgs.formats.yaml { };
  unrenderedConfig = settingsFormat.generate "corten-matrix-config.yaml" cfg.settings;
  renderedConfig = config.sops.templates."corten-matrix-config.yaml".path;

  # The bridge rewrites its config on startup (bridgev2 upgrades it in place
  # and the bridge splices in missing network keys), so it runs against a
  # writable copy in the data dir that is refreshed from the declarative,
  # secret-substituted template on every start. The CLI subcommands (`login`,
  # `logs`, …) find it there too, under $XDG_DATA_HOME/corten-matrix.
  startScript = pkgs.writeShellScript "corten-matrix-start" ''
    set -euo pipefail

    # sops-nix renders the template from its own launchd daemon at boot.
    until [ -r ${renderedConfig} ]; do
      sleep 2
    done

    mkdir -p ${cfg.dataDir}/logs
    install -m 600 ${renderedConfig} ${cfg.dataDir}/config.yaml

    cd ${cfg.dataDir}
    exec ${lib.getExe cfg.package} -c ${cfg.dataDir}/config.yaml
  '';
in
{
  options.custom.services.corten-matrix = {
    enable = mkEnableOption "corten-matrix, a Matrix-iMessage bridge";

    package = mkPackageOption pkgs [ "custom" "corten-matrix" ] { };

    user = mkOption {
      type = types.str;
      default = config.meta.flake.owner;
      description = ''
        macOS user the bridge runs as. It must be signed into iCloud so the
        bridge can register with Apple natively.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.meta.flake.ownerHome}/.local/share/corten-matrix";
      description = ''
        Bridge state: the rendered config, SQLite database, iMessage session
        and logs. Must be the upstream default (`$XDG_DATA_HOME/corten-matrix`)
        for the `corten-matrix` CLI subcommands to find it.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 29332;
      description = "Port the appservice listens on for the homeserver.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address the appservice binds to. The homeserver is on another host, so not loopback.";
    };

    homeserver = {
      address = mkOption {
        type = types.str;
        example = "https://matrix.example.com";
        description = "Client-server API URL of the homeserver.";
      };

      domain = mkOption {
        type = types.str;
        example = "example.com";
        description = "server_name of the homeserver.";
      };
    };

    adminUser = mkOption {
      type = types.str;
      example = "@you:example.com";
      description = "Matrix ID that gets admin rights on the bridge.";
    };

    settings = mkOption {
      type = settingsFormat.type;
      default = { };
      description = ''
        Bridge configuration, written to config.yaml. Merged over the module
        defaults. Secrets go in via `config.sops.placeholder.<name>`: the
        file is rendered as a sops template, so the Nix store only ever holds
        the placeholder strings.

        Network options are documented in
        <https://github.com/lrhodin/corten-matrix#key-options>.
      '';
    };
  };

  config = mkIf cfg.enable {
    custom.services.corten-matrix.settings = {
      network = {
        displayname_template = mkDefault "{{if .FirstName}}{{.FirstName}}{{if .LastName}} {{.LastName}}{{end}}{{else if .Nickname}}{{.Nickname}}{{else if .Phone}}{{.Phone}}{{else if .Email}}{{.Email}}{{else}}{{.ID}}{{end}}";
        # Off upstream too: enabling it asks for a device PIN at login to join
        # the iCloud Keychain, so it is an explicit opt-in.
        cloudkit_backfill = mkDefault false;
        backfill_source = mkDefault "cloudkit";
        # libheif and ffmpeg are bundled by the package, so both conversions
        # can simply be on.
        heic_conversion = mkDefault true;
        heic_jpeg_quality = mkDefault 95;
        video_transcoding = mkDefault true;
        max_attachment_size_mb = mkDefault 100;
        url_previews_in_backfill = mkDefault true;
        preferred_handle = mkDefault "";
        bridge_filtered_chats = mkDefault false;
        disable_facetime = mkDefault false;
        statuskit_share_on_startup = mkDefault true;
        statuskit_notifications = mkDefault true;
        debug_disable_privacy = mkDefault false;
        read_receipts = mkDefault true;
        typing_notifications = mkDefault true;
        carddav = {
          email = mkDefault "";
          url = mkDefault "";
          username = mkDefault "";
          password_encrypted = mkDefault "";
        };
      };

      bridge = {
        command_prefix = mkDefault "!im";
        personal_filtering_spaces = mkDefault true;
        private_chat_portal_meta = mkDefault true;
        relay.enabled = mkDefault false;
        permissions = {
          "*" = mkDefault "relay";
          ${cfg.homeserver.domain} = mkDefault "user";
          ${cfg.adminUser} = mkDefault "admin";
        };
      };

      database = {
        # SQLite is the only database upstream develops and tests against.
        type = mkDefault "sqlite3-fk-wal";
        uri = mkDefault "file:${cfg.dataDir}/corten-matrix.db?_txlock=immediate";
        max_open_conns = mkDefault 5;
        max_idle_conns = mkDefault 1;
      };

      homeserver = {
        address = mkDefault cfg.homeserver.address;
        domain = mkDefault cfg.homeserver.domain;
        software = mkDefault "standard";
        async_media = mkDefault false;
      };

      appservice = {
        address = mkDefault "http://${cfg.listenAddress}:${toString cfg.port}";
        hostname = mkDefault cfg.listenAddress;
        port = mkDefault cfg.port;
        id = mkDefault "imessage";
        bot = {
          username = mkDefault "imessagebot";
          displayname = mkDefault "iMessage bridge bot";
          avatar = mkDefault "mxc://maunium.net/tManJEpANASZvDVzvRvhILdl";
        };
        ephemeral_events = mkDefault true;
        username_template = mkDefault "imessage_{{.}}";
      };

      matrix = {
        message_status_events = mkDefault false;
        delivery_receipts = mkDefault false;
        message_error_notices = mkDefault true;
        sync_direct_chat_list = mkDefault true;
        federate_rooms = mkDefault true;
      };

      # The provisioning API is only used by Beeper-style frontends.
      provisioning.shared_secret = mkDefault "disable";

      # What the upstream installer writes: iMessage chats can hold tens of
      # thousands of messages, so deliver all history in one forward pass.
      backfill = {
        enabled = mkDefault true;
        max_initial_messages = mkDefault 2147483647;
        max_catchup_messages = mkDefault 5000;
        queue = {
          enabled = mkDefault true;
          batch_size = mkDefault 10000;
          batch_delay = mkDefault 1;
          max_batches = mkDefault (-1);
        };
      };

      encryption = {
        allow = mkDefault false;
        default = mkDefault false;
      };

      logging = {
        min_level = mkDefault "info";
        writers = mkDefault [
          {
            type = "stdout";
            format = "pretty";
          }
          {
            # What `corten-matrix logs` tails; relative to the data dir.
            type = "file";
            format = "json";
            filename = "./logs/bridge.log";
            max_size = 100;
            max_backups = 10;
            compress = false;
          }
        ];
      };
    };

    sops.templates."corten-matrix-config.yaml" = {
      file = unrenderedConfig;
      owner = cfg.user;
      mode = "0400";
    };

    environment.systemPackages = [ cfg.package ];

    launchd.user.agents.corten-matrix = {
      command = toString startScript;
      serviceConfig = {
        Label = label;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 5;
        WorkingDirectory = cfg.dataDir;
        StandardOutPath = "${cfg.dataDir}/logs/bridge.stdout.log";
        StandardErrorPath = "${cfg.dataDir}/logs/bridge.stdout.log";
        # launchd hands agents a soft limit of 256 open files, which a bridge
        # with many portals exhausts over time.
        SoftResourceLimits.NumberOfFiles = 65536;
        HardResourceLimits.NumberOfFiles = 65536;
      };
    };

    # launchd creates the log file but not its directory.
    system.activationScripts.postActivation.text = ''
      /usr/bin/sudo -u ${cfg.user} /bin/mkdir -p ${cfg.dataDir}/logs
    '';
  };
}
