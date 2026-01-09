{ config, lib, ... }:
let
  ports = lib.custom.mkUniqueValueAttrSet {
    name = "ports";
  };
in
{
  options.ports = ports.option;

  config.assertions = [
    (ports.assertion config)
  ];

  config.ports = {
    mosquitto_mqtt = 1883;
    mxroute-manager = 2121;
    immich = 2283;
    immich-ml = 2284;
    rmfakecloud = 3000;
    pairdrop = 3002;
    homepage = 3010;
    recommendarr = 3033;
    suggestarr = 3034;
    karakeep = 3091;
    unifi_stun = 3478;
    searxng = 3479;
    navidrome = 4533;
    soulseek_web = 5030;
    jellyseerr = 5055;
    changedetection = 5056;
    bazarr = 6767;
    profilarr = 6868;
    radarr = 7878;
    paperless = 8010;
    unifi_comm = 8080;
    booklore = 8082;
    ephemera = 8085;
    mylar3 = 8090;
    kapowarr = 8091;
    music-assistant_web = 8095;
    jellyfin = 8096;
    music-assistant_player = 8097;
    multi-scrobbler = 8098;
    homeassistant = 8123;
    matrix-synapse = 8124;
    matrix-mas = 8125;
    matrix-gvoice = 8126;
    byparr = 8191;
    flaresolverr = 8192;
    metadata-remote = 8338;
    kavita = 8345;
    syncthing = 8384;
    unifi = 8443;
    freshrss = 8487;
    vaultwarden = 8488;
    notesnook-s3 = 8490;
    notesnook-identity = 8491;
    notesnook-server = 8492;
    notesnook-sse = 8493;
    notesnook-monograph = 8494;
    lidarr = 8686;
    sonarr = 8989;
    mosquitto_mqtt-websockets = 9001;
    qbittorrent_web = 9090;
    qbittorrent_torrent = 9091;
    sabnzbd = 9092;
    prometheus-node-exporter = 9100;
    prometheus-zfs-exporter = 9101;
    prometheus-podman-exporter = 9102;
    prometheus-nut-exporter = 9103;
    prometheus-nixos-exporter = 9104;
    prometheus-systemd-exporter = 9105;
    prometheus-user-systemd-exporter = 9106;
    prometheus-quadlet-exporter = 9107;
    prometheus-blackbox-exporter = 9108;
    prometheus-mikrotik-exporter = 9109;
    prometheus-unifi-exporter = 9110;
    prometheus-jellyfin-exporter = 9111;
    prometheus-mqtt-exporter = 9112;
    prowlarr = 9696;
    huntarr = 9705;
    mealie = 9925;
    prometheus-alertmanager = 9995;
    loki = 9996;
    alloy = 9997;
    prometheus = 9998;
    grafana = 9999;
    scrypted = 10443;
    cleanuparr = 11011;
    syncthing_discovery = 21027;
    syncthing_sync = 22000;
    soulseek_dl = 50300;
    wireguard = 51820;
    glances = 61208;
  };
}
