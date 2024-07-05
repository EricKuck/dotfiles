{
  lib,
  config,
  pkgs,
  format,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.rust;
in
{
  options.custom.environments.rust = {
    enable = mkEnableOption "rust";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [ "rustrover" ];
    };
  };
}
