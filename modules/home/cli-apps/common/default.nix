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
        nixfmt
        nix-search-cli
        nvd
        nil
        nix-output-monitor
        nix-prefetch-git
        fd
        ripgrep
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
        sd
        dua
        usbutils
        gnupg1
        chafa
        claude-code
        unstable.nix-init
      ];

      sessionVariables = {
        EDITOR = "${lib.getExe pkgs.unstable.helix}";
        VISUAL = "${lib.getExe pkgs.unstable.helix}";
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
        icat = "chafa";
      };

      file = {
        ".hammerspoon".source = ../configs/hammerspoon;
      };
    };

    programs = {
      fish = {
        enable = true;

        functions = {
          set_fish_title = {
            body = ''
              read -p 'set_color green; echo -n "Enter tab title: "; set_color normal' -g FISH_TITLE
              commandline -f repaint
            '';
          };

          fish_title = {
            body = ''
              if test $FISH_TITLE
                if test $argv
                  echo -sn "[$FISH_TITLE] $argv"
                else
                  echo -sn $FISH_TITLE
                end
                return
              end

              if test $SSH_CONNECTION
                echo -sn "🌐 "
              end

              if test $argv
                echo -sn $argv
                return
              end

              set -l dir (pwd | string replace "$HOME" '~')
              set -l parts (string split '/' $dir)
              set -l shortened_path false

              while test (string length $dir) -gt 25; and test (count $parts) -gt 2
                set shortened_path true
                set dir (string join '/' $parts[2..-1])
                set parts (string split '/' $dir)
              end

              if $shortened_path
                set dir '…/'$dir
              end

              echo -sn $dir
            '';
          };
        };

        shellInit = ''
          set -x EDITOR ${lib.getExe pkgs.unstable.helix}
        '';

        interactiveShellInit = ''
          set fish_greeting

          if test "$COLORTERM" = truecolor || test "$TERM" = xterm-ghostty
            set -g fish_term24bit 1
            set -g COLORTERM truecolor
          end

          bind \ct set_fish_title
          bind alt-backspace backward-kill-word
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
        package = pkgs.unstable.helix;
        settings = builtins.fromTOML (builtins.readFile ../configs/helix/config.toml);

        languages.language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${lib.getExe pkgs.nixfmt}";
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

      zoxide = {
        enable = true;
        enableFishIntegration = true;
      };
    };

    xdg.configFile = {
      "lazygit/config.yml".source = ../configs/lazygit/config.yml;
      "karabiner/karabiner.json".source = ../configs/karabiner/karabiner.json;
      "bat".source = ../configs/bat;
      "ghostty".source = ../configs/ghostty;

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
