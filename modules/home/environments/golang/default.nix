{
  lib,
  pkgs,
  inputs,
  system,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.golang;
in
{
  options.custom.environments.golang = {
    enable = mkEnableOption "golang";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [ go ];
    };
  };
}
