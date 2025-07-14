{
  lib,
  config,
  osConfig,
  ...
}:

let
  # Every container gets the timezone
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

  # If a container sets its user, set process id env vars to avoid changing it at the process level
  addUserEnv =
    name: container:
    let
      containerConfig = container.containerConfig or { };
      user = containerConfig.user or null;
    in
    if user != null then
      container
      // {
        containerConfig = container.containerConfig or { } // {
          environments = (container.containerConfig.environments or { }) // {
            PUID = "0";
            PGID = "0";
          };
        };
      }
    else
      container;

  processContainer = name: container: addTimezone (addUserEnv name container);
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

  config = {
    virtualisation.quadlet = {
      autoEscape = true;
      containers = lib.mapAttrs processContainer config.quadlets.containers;
      networks = config.quadlets.networks;
      pods = config.quadlets.pods;
    };
  };
}
