{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;

  runnerUser = "gha-runner";
  runnerGroup = "gha-runner";
  workRoot = "/var/lib/gha-runner-work";
  # Survives ephemeral runs: rustup toolchains and the cargo registry, not build output.
  cacheDir = "/var/cache/gha-runner";

  # Jobs run inside the unit's sandbox, which rules out containers: Postgres
  # comes from here instead of a service container, and the server image is
  # cross-linked with zig and pushed with crane instead of built by Docker.
  extraPackages = with pkgs; [
    rustup
    gcc
    gnumake
    pkg-config
    zig
    cargo-zigbuild
    go-containerregistry
    postgresql_16
    nodejs_22
    python3
    openssh
    curl
    jq
    gawk
    gnugrep
    gnused
    findutils
    diffutils
    which
    unzip
    xz
    zstd
  ];
in
{
  options.gha-runner.irl.runners = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          tokenFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to file containing the runner's registration token.";
          };

          url = lib.mkOption {
            type = lib.types.str;
            default = "https://github.com/Infinite-Retry";
            description = ''
              Organization or repository the runner registers with. A repository
              URL makes the runner pick up jobs from that repository only.
            '';
          };

          ephemeral = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Take one job, then re-register with an empty state and work
              directory, which is also the job's HOME. Needs tokenFile to hold
              a PAT, since the runner registers again after every job.
            '';
          };

          extraLabels = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Labels in addition to the default self-hosted, Linux and X64.";
          };
        };
      }
    );
    default = { };
    description = "Infinite-Retry GitHub Actions runners, keyed by runner name.";
  };

  config = lib.mkIf (cfg != { }) {
    users = {
      groups.${runnerGroup} = { };
      users.${runnerUser} = {
        isSystemUser = true;
        group = runnerGroup;
        description = "GitHub Actions runners";
      };
    };

    # The default work directory is under /run, which is RAM.
    systemd.tmpfiles.rules = [
      "d ${workRoot} 0755 root root -"
    ]
    ++ lib.mapAttrsToList (name: _: "d ${workRoot}/${name} 0700 ${runnerUser} ${runnerGroup} -") cfg;

    services.github-runners = lib.mapAttrs (name: runner: {
      enable = true;
      inherit name;
      inherit (runner) url ephemeral extraLabels;
      tokenFile = toString runner.tokenFile;
      replace = true;
      user = runnerUser;
      group = runnerGroup;
      workDir = "${workRoot}/${name}";
      inherit extraPackages;
      extraEnvironment = {
        RUSTUP_HOME = "${cacheDir}/rustup";
        CARGO_HOME = "${cacheDir}/cargo";
      };
      serviceOverrides = {
        CacheDirectory = baseNameOf cacheDir;
        CacheDirectoryMode = "0700";
      };
    }) cfg;
  };
}
