{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.nut = {
    enable = true;
    port = config.ports.prometheus-nut-exporter;
    systemd = {
      execStart = "${lib.getExe pkgs.bash} -c 'NUT_EXPORTER_PASSWORD=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.upsmon_user_pw.path}) ${lib.getExe pkgs.prometheus-nut-exporter} --nut.server=localhost --web.listen-address=localhost:${toString config.ports.prometheus-nut-exporter} --nut.username=upsmon'";
      createUser = false;
      user = "upsmon";
      group = "upsmon";
    };
    scrape.metricsPath = "/ups_metrics";
    rules = [
      {
        name = "power";
        rules = [
          {
            alert = "PowerOutage";
            expr = ''network_ups_tools_ups_status{flag="OL"} == 0'';
            annotations = {
              summary = "UPS no longer on line";
            };
          }
          {
            alert = "UPSLowBattery";
            expr = ''network_ups_tools_ups_status{flag="LB"} == 1'';
            annotations = {
              summary = "UPS low battery";
            };
          }
        ];
      }
    ];
  };
}
