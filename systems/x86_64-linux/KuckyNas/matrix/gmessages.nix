{
  config,
  lib,
  pkgs,
  ...
}:
let
  bridgeLib = import ./bridge.nix { inherit config lib; };
in
{
  services.custom.matrix-bridges.gmessages = bridgeLib.mkBridgeConfig {
    service = "gmessages";
    serviceName = "Google Messages";
    package = pkgs.mautrix-gmessages;
    commandPrefix = "!gm";
    botAvatar = "mxc://maunium.net/ygtkteZsXnGJLJHRchUwYWak";

    settings = {
      network = {
        max_connections = 3;
      };
    };
  };
}
