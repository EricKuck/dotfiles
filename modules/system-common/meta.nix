{
  config,
  lib,
  system,
  ...
}:
{
  options.meta = {
    flake = {
      owner = lib.mkOption {
        type = lib.types.str;
        default = "eric";
      };

      ownerHome = lib.mkOption {
        type = lib.types.str;
        default =
          if (lib.snowfall.system.is-darwin system) then
            "/Users/${config.meta.flake.owner}"
          else
            "/home/${config.meta.flake.owner}";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default =
          if (lib.snowfall.system.is-darwin system) then
            "${config.meta.flake.ownerHome}/.config/nix"
          else
            "${config.meta.flake.ownerHome}/.config/nixos";
      };
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
    };

    containerData = lib.mkOption {
      type = lib.types.str;
    };
  };
}
