{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.workstation;
in
{
  options.custom.environments.workstation = {
    enable = mkEnableOption "workstation";
  };

  config = mkIf cfg.enable {
    custom = {
      cli-apps = {
        common.enable = true;
      };
    };

    home.packages = with pkgs; [
      poppler-utils
      imagemagickBig
      ffmpeg
      svgo
      claude-code
      (writeShellScriptBin "activate-btt" (builtins.readFile ./scripts/activate-btt))
      (writeShellScriptBin "activate-istat" (builtins.readFile ./scripts/activate-istat))
      (writeShellScriptBin "scanify" (builtins.readFile ./scripts/scanify))
      (stdenv.mkDerivation {
        name = "switch-orion-window";
        src = ./scripts/switch-orion-window;
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir -p $out/bin
          cp $src $out/bin/switch-orion-window
          chmod +x $out/bin/switch-orion-window
        '';
      })
    ];
  };
}
