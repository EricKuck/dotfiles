{
  lib,
  config,
  osConfig,
  ...
}:

let
  addTimezone =
    container:
    container
    // {
      containerConfig = container.containerConfig or { } // {
        environments = (container.containerConfig.environments or { }) // {
          TZ = osConfig.meta.timezone;
        };
      };
    };
in
{
  options.quadlets = {
    containers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };

    networks = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };

    pods = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };

  config.virtualisation.quadlet = {
    autoEscape = true;
    containers = lib.mapAttrs (_name: addTimezone) config.quadlets.containers;
    networks = config.quadlets.networks;
    pods = config.quadlets.pods;
  };
}
