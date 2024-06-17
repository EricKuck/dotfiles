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
  cfg = config.custom.cli-apps.common;
in
{
  options.custom.cli-apps.common = {
    enable = mkEnableOption "common";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        inputs.nix-inspect.packages.${system}.default
        inputs.nixpkgs-unstable.legacyPackages.${system}.nixfmt-rfc-style
        nix-search-cli
        helix
        neovim
        nnn
        fd
        ripgrep
        fzf
        btop
        iftop
        htop
        bat
        grc
        curl
        wget
        jq
        zip
        unzip
        yazi
        git
        git-lfs
        lazygit
        delta
        gh
        eza
      ];

      sessionVariables = {
        EDITOR = "hx";
        VISUAL = "hx";
        EZA_COLORS = "ur=32:uw=32:ux=32:ue=32:gr=33:gw=33:gx=33:tr=31:tw=31:tx=31";
      };

      shellAliases = {
        lg = "lazygit";
        vi = "nvim";
        cat = "bat --style=plain --no-pager";
        ls = "eza -g";
      };
    };

    programs = {
      fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting
        '';

        plugins = [
          {
            name = "grc";
            src = pkgs.fishPlugins.grc.src;
          }
          {
            name = "fzf-fish";
            src = pkgs.fishPlugins.fzf-fish.src;
          }
          {
            name = "to";
            src = pkgs.fetchFromGitHub {
              owner = "joehillen";
              repo = "to-fish";
              rev = "52b151cfe67c00cb64d80ccc6dae398f20364938";
              sha256 = "DfDsU/qY2XdYlkLISIOv02ggHfKEpb+YompNWWjs5/A=";
            };
          }
          {
            name = "prompt";
            src = ./fish-prompt;
          }
        ];
      };
    };
  };
}
