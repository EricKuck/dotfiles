{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.node = {
    enable = true;
    port = config.ports.prometheus-node-exporter;
    systemd.execStart = "${lib.getExe pkgs.prometheus-node-exporter} --web.listen-address localhost:${toString config.ports.prometheus-node-exporter}";
    rules = [
      {
        name = "zfs";
        rules = [
          {
            alert = "ZPoolStatusDegraded";
            expr = ''node_zfs_zpool_state{state!="online"} > 0'';
            annotations = {
              summary = "ZFS pool degraded";
              description = ''Pool degraded on {{ $labels.zpool }}'';
            };
          }
        ];
      }
      {
        name = "machine";
        rules = [
          {
            alert = "TemperatureHigh";
            expr = ''node_hwmon_temp_celsius > node_hwmon_temp_max_celsius'';
            for = "2m";
            annotations = {
              summary = "Something is literally on fire";
              description = ''{{ $value }} degrees on {{ $labels.chip }}'';
            };
          }
          {
            alert = "FilesystemScrapeErrors";
            expr = ''node_filesystem_device_error{fstype!~"tmpfs|fuse.*|ramfs"} > 0'';
            annotations = {
              description = ''{{ $value }} filesystem scrape errors registered on {{ $labels.mountpoint }}'';
            };
          }
          {
            alert = "DiskSpaceLow";
            expr = ''round((node_filesystem_avail_bytes{fstype!~"(ramfs|tmpfs)"} / node_filesystem_size_bytes) * 100, 0.01) < 10'';
            annotations = {
              summary = "Filesystem space use > 90%";
              description = ''S{{ $value }}% free on {{ $labels.mountpoint }}'';
            };
          }
          {
            alert = "LowMemory";
            expr = ''round(node_memory_MemAvailable_bytes / 1024 / 1024 / 1024, 0.01) < 5'';
            for = "5m";
            annotations = {
              summary = "Running out of memory";
              description = ''Node memory is filling up: {{ $value }}GB remaining'';
            };
          }
          {
            alert = "MemoryPressure";
            expr = ''round(rate(node_vmstat_pgmajfault[5m]), 0.01) > 1000'';
            annotations = {
              summary = "Under memory pressure";
              description = ''The node is under heavy memory pressure: {{ $value }}'';
            };
          }
        ];
      }
    ];
  };
}
