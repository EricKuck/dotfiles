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
    jellyseerr = 5055;
    bazarr = 6767;
    profilarr = 6868;
    radarr = 7878;
    paperless = 8010;
    unifi_comm = 8080;
    calibre = 8083;
    calibre-downloader = 8084;
    mylar3 = 8090;
    music-assistant = 8095;
    jellyfin = 8096;
    homeassistant = 8123;
    flaresolverr = 8191;
    kavita = 8345;
    syncthing = 8384;
    unifi = 8443;
    freshrss = 8487;
    vaultwarden = 8488;
    obsidian-sync = 8489;
    sonarr = 8989;
    mosquitto_mqtt-websockets = 9001;
    qbittorrent = 9090;
    qbittorrent_torrent = 9091;
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
    wyoming-piper = 10200;
    wyoming-whisper = 10300;
    wyoming-openwakeword = 10400;
    scrypted = 10443;
    cleanuparr = 11011;
    syncthing_discovery = 21027;
    syncthing_sync = 22000;
    wireguard = 51820;
    glances = 61208;
  };
}
