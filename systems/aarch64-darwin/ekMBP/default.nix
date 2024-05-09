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
      duo_gen = "/Users/erickuck/Code/macOS/duo-2fa/duo_gen.py /Users/erickuck/Code/macOS/duo-2fa/duotoken.hotp";
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

  users.users.erickuck = {
    name = "erickuck";
    home = "/Users/erickuck";
  };

  system.stateVersion = 4;
}
