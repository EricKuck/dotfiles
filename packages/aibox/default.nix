{
  lib,
  stdenv,
  rustPlatform,
  darwin,
  bubblewrap,
  procps,
  git,
  coreutils,
  gnused,
  gnugrep,
  findutils,
}:

let
  # Pinned into the CLI so its helpers resolve regardless of the caller's PATH.
  # The session inherits it, which is what puts a usable ps in front of the
  # harness: Apple's /bin/ps is setuid root and Seatbelt refuses to exec a
  # setuid binary, so agent hooks that resolve their own pid and tty through it
  # come up empty inside the sandbox. This build carries no setuid bit. On Linux
  # bwrap is the sandbox itself, so it has to be here too.
  runtimePath = lib.makeBinPath (
    [
      git
      coreutils
      findutils
      gnused
      gnugrep
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.ps ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      bubblewrap
      procps
    ]
  );

  # Each harness name dispatches on argv[0] back into the same CLI.
  harnesses = [
    "claude"
    "pi"
  ];
in
rustPlatform.buildRustPackage {
  pname = "aibox";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # cargo installs the native core as aibox-host; add the CLI beside it, pin its
  # runtime PATH, and point each harness symlink at it.
  postInstall = ''
    install -m755 bin/aibox $out/bin/aibox
    substituteInPlace $out/bin/aibox \
      --replace-fail 'AIBOX_RUNTIME_PATH=""' 'AIBOX_RUNTIME_PATH="${runtimePath}"'
    ${lib.concatMapStringsSep "\n" (h: "ln -s aibox $out/bin/${h}") harnesses}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x $out/bin/aibox-host
    for n in aibox ${lib.concatStringsSep " " harnesses}; do
      test -x "$out/bin/$n" || { echo "missing $n"; exit 1; }
    done
    grep -q 'AIBOX_RUNTIME_PATH="/nix/store' $out/bin/aibox

    runHook postInstallCheck
  '';

  meta = {
    description = "Run AI coding harnesses inside a filesystem sandbox with live directory grants";
    longDescription = ''
      A sandbox host for Claude and Pi coding harnesses, built on Seatbelt on
      macOS and bubblewrap on Linux. Provides claude and pi wrappers that launch
      (or reuse) a per-project sandbox with the same filesystem allow-listing as
      the container -- workspace read-write, agent config and build caches
      read-write, system and toolchain read-only, everything else denied -- and
      lets directories be added to or removed from the running session live,
      through sandbox extensions on macOS and mount propagation on Linux. No
      network isolation.
    '';
    mainProgram = "aibox";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
