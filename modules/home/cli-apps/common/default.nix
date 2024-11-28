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
        nvd
        nix-output-monitor
        nix-prefetch-git
        neovim
        nnn
        fd
        ripgrep
        btop
        iftop
        htop
        bat
        grc
        killall
        curl
        wget
        jq
        zip
        unzip
        git
        git-lfs
        lazygit
        delta
        gh
        eza
        figlet
        lolcat
        ffmpeg
        unstable.serpl
        unstable.nix-init
      ];

      sessionVariables = {
        EDITOR = "${lib.getExe pkgs.helix}";
        VISUAL = "${lib.getExe pkgs.helix}";
        EZA_COLORS = "ur=32:uw=32:ux=32:ue=32:gr=33:gw=33:gx=33:tr=31:tw=31:tx=31";
        grc_plugin_ignore_execs = "lolcat";
      };

      shellAliases = {
        lg = "lazygit";
        vi = "nvim";
        cat = "bat --style=plain --no-pager";
        ls = "eza -g";
        nix-shell = "nix-shell --run fish";
        flake-repl = "nix repl --expr \"builtins.getFlake $FLAKE\"";
        wssh = "wezterm cli spawn --domain-name";
      };
    };

    programs = {
      fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting

          if test "$COLORTERM" = truecolor || test "$TERM" = xterm-kitty
            set -g fish_term24bit 1
            set -g COLORTERM truecolor
          end

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

      helix = {
        enable = true;
        settings = builtins.fromTOML (builtins.readFile ../configs/helix/config.toml);

        languages.language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${lib.getExe
              inputs.nixpkgs-unstable.legacyPackages.${system}.nixfmt-rfc-style
            }";
          }
        ];
      };

      yazi = {
        enable = true;
        theme = {
          flavor = {
            use = "catppuccin-frappe";
          };
        };
      };

      fzf = {
        enable = true;
        colors = builtins.fromTOML (builtins.readFile ../configs/fzf/colors.toml);
      };
    };

    xdg.configFile = {
      "helix/yazi-picker.sh".source = ../configs/helix/yazi-picker.sh;
      "lazygit/config.yml".source = ../configs/lazygit/config.yml;
      "bat".source = ../configs/bat;
      "kitty".source = ../configs/kitty;
      "wezterm".source = ../configs/wezterm;

      # The main branch has a flavors attribute for yazi, but it's not in the release yet. Revisit if this is needed.
      "yazi/flavors".source = pkgs.fetchFromGitHub {
        owner = "yazi-rs";
        repo = "flavors";
        rev = "2d7dd2afe253c30943e9cd05158b1560a285eeab";
        hash = "sha256-566RFL1Wng7yr5OS3UtKEy+ZLrgwfCdX9FAtwRQK2oM=";
      };
    };
  };
}
