{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.hardware.coral;
in
{
  options.custom.hardware.coral = {
    enable = lib.mkEnableOption "coral";
  };

  config = mkIf cfg.enable {
    services.udev.packages = [ pkgs.custom.libedgetpu ];
    users.groups.plugdev = { };
    boot.extraModulePackages = [ pkgs.unstable.linuxKernel.packages.linux_6_8.gasket ];
  };
}
