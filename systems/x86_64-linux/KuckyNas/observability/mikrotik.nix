{
  config,
  lib,
  pkgs,
  ...
}:
let
  PORT = config.ports.prometheus-mikrotik-exporter;

  mktxpConfig = pkgs.lib.generators.toINI { } {
    router = {
      hostname = "192.168.1.1";
      username = "prometheus";
      password_file = config.sops.secrets.mikrotik_pw.path;
    };
    default = {
      enabled = true;
      port = 8728;
      hostname = "localhost";
      username = "mktxp";
      password = "changeme";
      password_file = "";
      health = true;
      use_ssl = false;
      no_ssl_certificate = false;
      ssl_certificate_verify = false;
      ssl_ca_file = "";
      plaintext_login = true;
      installed_packages = false;
      dhcp = true;
      dhcp_lease = true;
      connections = true;
      connection_stats = true;
      interface = true;
      route = true;
      pool = true;
      firewall = true;
      neighbor = true;
      dns = true;
      ipv6_route = false;
      ipv6_pool = false;
      ipv6_firewall = false;
      ipv6_neighbor = false;
      poe = true;
      monitor = false;
      netwatch = false;
      public_ip = true;
      wireless = false;
      wireless_clients = false;
      capsman = false;
      capsman_clients = false;
      eoip = false;
      gre = false;
      ipip = false;
      lte = false;
      ipsec = false;
      switch_port = false;
      kid_control_assigned = false;
      kid_control_dynamic = false;
      user = true;
      queue = false;
      bgp = false;
      bfd = false;
      routing_stats = false;
      certificate = false;
      remote_dhcp_entry = null;
      remote_capsman_entry = null;
      use_comments_over_names = true;
      check_for_updates = false;
    };
  };

  mktxpSystemConfig = pkgs.lib.generators.toINI { } {
    MKTXP = {
      listen = "0.0.0.0:${toString PORT}";
      socket_timeout = 5;
      initial_delay_on_failure = 120;
      max_delay_on_failure = 900;
      delay_inc_div = 5;
      bandwidth = false;
      bandwidth_test_interval = 600;
      minimal_collect_interval = 5;
      verbose_mode = false;
      fetch_routers_in_parallel = false;
      max_worker_threads = 5;
      max_scrape_duration = 30;
      total_max_scrape_duration = 90;
      compact_default_conf_values = false;
    };
  };

  configFileDir = pkgs.runCommand "mktxp_conf" { } ''
    mkdir -p $out
    echo '${mktxpConfig}' > $out/mktxp.conf
    echo '${mktxpSystemConfig}' > $out/_mktxp.conf
  '';
  configFile = pkgs.writeText "mktxp.conf" mktxpConfig;
in
{
  sops.secrets.mikrotik_pw = { };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "mikrotik";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString PORT}" ];
        }
      ];
    }
  ];

  systemd.services = {
    prometheus-mikrotik-exporter = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [
        pkgs.which
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "60s";
        ExecStart = "${lib.getExe pkgs.mktxp} --cfg-dir ${configFileDir} export";
      };
    };
  };
}
