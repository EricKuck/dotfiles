{
  description = "System config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nix-inspect.url = "github:bluskript/nix-inspect";

    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
  };

  outputs =
    {
      self,
      snowfall-lib,
      treefmt-nix,
      sops-nix,
      nixpkgs-unstable,
      systems,
      ...
    }@inputs:
    let
      lib = snowfall-lib.mkLib {
        inherit inputs;
        src = ./.;

        snowfall = {
          meta = {
            name = "custom";
            title = "Custom Flake";
          };

          namespace = "custom";
        };
      };

      eachSystem =
        f:
        nixpkgs-unstable.lib.genAttrs (import systems) (
          system: f nixpkgs-unstable.legacyPackages.${system}
        );

      treefmtEval = eachSystem (
        pkgs:
        treefmt-nix.lib.evalModule pkgs (pkgs: {
          projectRootFile = "flake.nix";
          settings.global.excludes = [ "./result/**" ];

          programs.nixfmt.enable = true; # *.nix
          programs.black.enable = true; # *.py
          programs.shellcheck.enable = true;
          settings.formatter.shellcheck.excludes = [
            "modules/darwin/environments/common/fileicon"
          ];
        })
      );
    in
    lib.mkFlake {
      channels-config = {
        allowUnfree = true;
      };

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);

      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
      });

      systems.modules.nixos = lib.snowfall.fs.get-files-recursive ./modules/system-common ++ [
        inputs.quadlet-nix.nixosModules.quadlet
      ];
      systems.modules.darwin = lib.snowfall.fs.get-files-recursive ./modules/system-common;

      homes.modules = [ inputs.quadlet-nix.homeManagerModules.quadlet ];
    };
}
