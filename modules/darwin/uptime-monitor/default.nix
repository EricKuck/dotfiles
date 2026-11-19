{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optional
    types
    ;
  cfg = config.custom.services.uptime-monitor;
  owner = config.meta.flake.owner;
  home = config.meta.flake.ownerHome;
  stateDir = "${home}/Library/Application Support/uptime-monitor";
  blackboxAddress = "127.0.0.1:9115";
  alertmanagerAddress = "127.0.0.1:9093";

  toYAML = name: value: pkgs.writeText name (builtins.toJSON value);

  host = ''{{ reReplaceAll "^https?://([^/]+).*" "$1" $labels.target }}'';
  siteLink = ''{{ reReplaceAll "^(https?://[^/]+).*" "$1" $labels.target }}'';
  # A zero status code means no HTTP response arrived; a 200 means the body check failed.
  failureCause = ''{{ with query (printf "probe_http_status_code{target=%q}" $labels.target) }}{{ $code := . | first | value }}{{ if eq $code 0.0 }}no response (timeout or connection error){{ else if eq $code 200.0 }}unexpected response body{{ else }}HTTP {{ printf "%.0f" $code }}{{ end }}{{ else }}no probe result{{ end }}'';
  certExpiry = ''{{ with query (printf "probe_ssl_earliest_cert_expiry{target=%q}" $labels.target) }}{{ (. | first | value | toTime).Format "Jan 2" }}{{ end }}'';
  brokenPart = "{{ if $labels.service }}The {{ $labels.service }} probe on IRLBuild{{ else }}IRLBuild's probe exporter{{ end }}";

  blackboxConfig = toYAML "blackbox.yml" {
    modules = mapAttrs' (
      name: probe:
      nameValuePair name {
        prober = "http";
        timeout = "10s";
        http = {
          preferred_ip_protocol = "ip4";
          method = "GET";
          valid_status_codes = [ 200 ];
          # A Cloudflare Access login redirect must count as down.
          follow_redirects = false;
          fail_if_not_ssl = true;
          fail_if_body_not_matches_regexp = optional (probe.bodyRegex != null) probe.bodyRegex;
        };
      }
    ) cfg.probes;
  };

  rules = toYAML "uptime-rules.yml" {
    groups = [
      {
        name = "uptime";
        rules = [
          {
            alert = "ServiceDown";
            expr = "probe_success == 0";
            "for" = cfg.downFor;
            labels.severity = "critical";
            annotations = {
              title = ":red_circle: {{ $labels.service }} is down";
              resolved_title = "{{ $labels.service }} is back up";
              summary = "${host} is failing its health check: ${failureCause}.";
              resolved = "${host} is passing its health check again.";
              link = siteLink;
            };
          }
          {
            alert = "CertExpiringSoon";
            expr = "probe_ssl_earliest_cert_expiry - time() < 7 * 86400";
            "for" = "1h";
            labels.severity = "warning";
            annotations = {
              title = ":large_orange_circle: {{ $labels.service }}'s certificate expires soon";
              resolved_title = "{{ $labels.service }}'s certificate was renewed";
              summary = "The TLS certificate for ${host} expires ${certExpiry} and hasn't been renewed.";
              resolved = "The TLS certificate for ${host} has been renewed.";
              link = siteLink;
            };
          }
          {
            alert = "MonitorBroken";
            expr = "up == 0";
            "for" = "5m";
            labels.severity = "warning";
            annotations = {
              title = ":warning: Uptime monitoring is broken";
              resolved_title = "Uptime monitoring is working again";
              summary = "${brokenPart} isn't working, so outages won't be reported until this is fixed.";
              resolved = "${brokenPart} is working again.";
            };
          }
          {
            alert = "Watchdog";
            expr = "vector(1)";
            annotations.summary = "Always firing; proves the alert pipeline works";
          }
        ];
      }
    ];
  };

  prometheusConfig = toYAML "prometheus.yml" {
    global = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };
    rule_files = [ rules ];
    alerting.alertmanagers = [ { static_configs = [ { targets = [ alertmanagerAddress ]; } ]; } ];
    scrape_configs = [
      {
        job_name = "blackbox";
        static_configs = [ { targets = [ blackboxAddress ]; } ];
      }
    ]
    ++ mapAttrsToList (name: probe: {
      job_name = "probe_${name}";
      metrics_path = "/probe";
      params.module = [ name ];
      static_configs = [
        {
          targets = [ blackboxAddress ];
          labels = {
            target = probe.url;
            service = probe.name;
          };
        }
      ];
      relabel_configs = [
        {
          source_labels = [ "target" ];
          target_label = "__param_target";
        }
      ];
    }) cfg.probes;
  };

  alertmanagerConfig = toYAML "alertmanager.yml" {
    route = {
      receiver = "slack";
      group_by = [
        "alertname"
        "target"
      ];
      group_wait = "10s";
      group_interval = "5m";
      repeat_interval = "4h";
      routes = [
        {
          matchers = [ ''alertname="Watchdog"'' ];
          receiver = if cfg.heartbeatUrlFile != null then "heartbeat" else "null";
          group_wait = "0s";
          group_interval = "1m";
          repeat_interval = "1m";
        }
      ];
    };
    receivers = [
      {
        name = "slack";
        slack_configs = [
          {
            api_url_file = cfg.slackWebhookUrlFile;
            send_resolved = true;
            color = ''{{ if eq .Status "resolved" }}good{{ else if eq .CommonLabels.severity "warning" }}warning{{ else }}danger{{ end }}'';
            title_link = "{{ (index .Alerts 0).Annotations.link }}";
            title = ''{{ with index .Alerts 0 }}{{ if eq .Status "firing" }}{{ .Annotations.title }}{{ else }}:large_green_circle: {{ .Annotations.resolved_title }}{{ end }}{{ end }}'';
            text = ''{{ range .Alerts }}{{ if eq .Status "resolved" }}{{ .Annotations.resolved }}{{ "\n" }}Lasted {{ .EndsAt.Sub .StartsAt | humanizeDuration }}{{ else }}{{ .Annotations.summary }}{{ end }}{{ "\n" }}{{ end }}'';
          }
        ];
      }
      { name = "null"; }
    ]
    ++ optional (cfg.heartbeatUrlFile != null) {
      name = "heartbeat";
      webhook_configs = [
        {
          url_file = cfg.heartbeatUrlFile;
          send_resolved = false;
        }
      ];
    };
  };

  daemon = name: args: {
    serviceConfig = {
      ProgramArguments = args;
      UserName = owner;
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${home}/Library/Logs/uptime-monitor-${name}.log";
      StandardErrorPath = "${home}/Library/Logs/uptime-monitor-${name}.log";
    };
  };
in
{
  options.custom.services.uptime-monitor = {
    enable = mkEnableOption "external uptime probes with Slack alerts";

    probes = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              name = mkOption {
                type = types.str;
                default = name;
                description = "Name shown in Slack alerts.";
              };
              url = mkOption {
                type = types.str;
                example = "https://example.com/healthz";
              };
              bodyRegex = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "^ok$";
              };
            };
          }
        )
      );
      default = { };
    };

    downFor = mkOption {
      type = types.str;
      default = "2m";
      description = "How long a probe must fail before Slack is alerted.";
    };

    slackWebhookUrlFile = mkOption {
      type = types.str;
      description = "File holding a Slack incoming-webhook URL, readable by the owner.";
    };

    heartbeatUrlFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "File holding a dead-man's-switch ping URL (e.g. Healthchecks.io), hit about every minute while alerting works.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1:9090";
      description = "Prometheus listen address; widen it to let another Grafana use it as a data source.";
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons = {
      uptime-monitor-blackbox = daemon "blackbox" [
        (lib.getExe pkgs.prometheus-blackbox-exporter)
        "--config.file=${blackboxConfig}"
        "--web.listen-address=${blackboxAddress}"
      ];

      uptime-monitor-prometheus = daemon "prometheus" [
        (lib.getExe' pkgs.prometheus "prometheus")
        "--config.file=${prometheusConfig}"
        "--storage.tsdb.path=${stateDir}/prometheus"
        "--storage.tsdb.retention.time=90d"
        "--web.listen-address=${cfg.listenAddress}"
      ];

      uptime-monitor-alertmanager = daemon "alertmanager" [
        (lib.getExe' pkgs.prometheus-alertmanager "alertmanager")
        "--config.file=${alertmanagerConfig}"
        "--storage.path=${stateDir}/alertmanager"
        "--web.listen-address=${alertmanagerAddress}"
        "--cluster.listen-address="
      ];
    };
  };
}
