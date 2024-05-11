{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  environment = {
    shells = [ pkgs.fish ];

    systemPath = [ "/opt/homebrew/bin" ];

    shellAliases = {
      kopia = "/Applications/KopiaUI.app/Contents/Resources/server/kopia";
      gw = "gww";
    };
  };

  programs.fish.enable = true;

  homebrew = {
    enable = true;

    onActivation = {
      upgrade = true;
      autoUpdate = true;
      cleanup = "zap";
    };

    global = {
      autoUpdate = true;
      brewfile = true;
      lockfiles = true;
    };

    taps = [
      "mdogan/zulu"
      "pbreault/gww"
    ];

    brews = [
      "gradle-profiler"
      "pbreault/gww/gww"
    ];

    casks = [
      "1password"
      "kopiaui"
      "flipper"
      "orcaslicer"
      "obsidian"
      "nrlquaker-winbox"
      "macmediakeyforwarder"
      "lulu"
      "jetbrains-toolbox"
      "force-paste"
      "kitty"
      "zulu-jdk17"
    ];
  };

  users.users.erickuck = rec {
    home = "/Users/${config.users.users.erickuck.name}";
  };

  system.stateVersion = 4;
}
