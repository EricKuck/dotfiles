{ config, lib, ... }:
let
  uids = lib.custom.mkUniqueValueAttrSet {
    name = "uids";
  };

  mkOwners = attrs: lib.mapAttrs (_name: uid: "${toString uid}:${toString uid}") attrs;
in
{
  options = {
    uids = uids.option;

    serviceOwners = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "A map of uid:gid strings derived from the uids attribute set.";
      readOnly = true;
    };
  };

  config = {
    assertions = [
      (uids.assertion config)
    ];

    uids = {
      unifi = 999;

      jellyfin = 1004;
      syncthing = 1008;

      prowlarr = 1044;
      wireguard = 1048;
      arr = 1072;
      mealie = 1076;
      freshrss = 1240;

      vaultwarden = 3792;

      profilarr = 3992;
      cleanuparr = 3993;
    };

    serviceOwners = mkOwners config.uids;
  };
}
