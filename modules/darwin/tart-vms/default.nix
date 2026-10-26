{
  config,
  lib,
  pkgs,
  ...
}:

# Runs existing Tart VMs headless as launchd agents of the owner (whose
# ~/.tart holds them), with optional TCP forwards from the host to the guest.
#
# VMs stay on Tart's NAT network: bridging over Wi-Fi is unreliable, and this
# way the guest is reachable at the host's address. The guest's NAT address
# can change between boots, so each forwarded connection looks it up again.
#
# The forwards run as root: macOS only lets other processes reach local
# network addresses, the VM's included, with a Local Network permission a Nix
# store binary can't get. That holds even for daemons running as a user.
let
  inherit (lib)
    filterAttrs
    getExe
    listToAttrs
    mapAttrsToList
    mergeAttrsList
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    nameValuePair
    types
    ;

  cfg = config.custom.services.tart-vms;
  enabledVms = filterAttrs (_: vm: vm.enable) cfg.vms;
  tart = getExe cfg.package;
  socat = getExe pkgs.socat;
  ownerHome = config.meta.flake.ownerHome;
  logDir = "${ownerHome}/Library/Logs";

  runScript =
    name:
    pkgs.writeShellScript "tart-${name}-run" ''
      ${tart} run ${name} --no-graphics &
      vm=$!
      # launchd sends SIGTERM on unload and at shutdown; ask the guest to shut
      # down cleanly instead of pulling the plug on its disk.
      trap '${tart} stop ${name} --timeout 60; wait "$vm"' TERM INT
      wait "$vm"
    '';

  vmAgent = name: {
    command = toString (runScript name);
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      ExitTimeOut = 90;
      StandardOutPath = "${logDir}/tart-${name}.log";
      StandardErrorPath = "${logDir}/tart-${name}.log";
    };
  };

  # Run per connection. A script of its own because socat splits address
  # arguments on ':', so this can't be inlined into EXEC/SYSTEM.
  connectScript =
    name: fwd:
    pkgs.writeShellScript "tart-${name}-connect-${toString fwd.guest}" ''
      exec ${socat} STDIO TCP:"$(${tart} ip ${name})":${toString fwd.guest}
    '';

  forwardDaemon = name: fwd: {
    command = "${socat} TCP-LISTEN:${toString fwd.host},fork,reuseaddr EXEC:${connectScript name fwd}";
    serviceConfig = {
      # So `tart ip` finds the owner's VMs.
      EnvironmentVariables.TART_HOME = "${ownerHome}/.tart";
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "${logDir}/tart-${name}-forward-${toString fwd.host}.log";
    };
  };
in
{
  options.custom.services.tart-vms = {
    package = mkPackageOption pkgs "tart" { };

    vms = mkOption {
      default = { };
      description = "Tart VMs to keep running, by name (as in `tart list`).";
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkEnableOption "this VM" // {
              default = true;
            };

            forwardPorts = mkOption {
              default = [ ];
              description = "TCP ports on the host forwarded to the guest.";
              type = types.listOf (
                types.submodule {
                  options = {
                    host = mkOption { type = types.port; };
                    guest = mkOption { type = types.port; };
                  };
                }
              );
            };
          };
        }
      );
    };
  };

  config = mkIf (enabledVms != { }) {
    environment.systemPackages = [ cfg.package ];

    launchd.user.agents = lib.mapAttrs' (
      name: _: nameValuePair "tart-${name}" (vmAgent name)
    ) enabledVms;

    launchd.daemons = mergeAttrsList (
      mapAttrsToList (
        name: vm:
        listToAttrs (
          map (
            fwd: nameValuePair "tart-${name}-forward-${toString fwd.host}" (forwardDaemon name fwd)
          ) vm.forwardPorts
        )
      ) enabledVms
    );
  };
}
