{
  lib,
  stdenvNoCC,
  devpod,
  jq,
  git,
  gh,
  openssh,
  coreutils,
  gnugrep,
  gnused,
}:

let
  runtimePath = lib.makeBinPath [
    devpod
    jq
    git
    gh
    openssh
    coreutils
    gnugrep
    gnused
  ];

  # Each name dispatches on argv[0] back into the same script.
  harnesses = [
    "claude"
    "codex"
    "copilot"
    "opencode"
    "pi"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "aidev";
  version = "0.1.0";

  src = ./aidev;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 $src $out/bin/aidev

    # Pin runtime dependencies rather than wrapping: makeWrapper would replace
    # argv[0] with the wrapped path and break the symlink dispatch below.
    substituteInPlace $out/bin/aidev \
      --replace-fail 'AIDEV_RUNTIME_PATH=""' 'AIDEV_RUNTIME_PATH="${runtimePath}"'

    ${lib.concatMapStringsSep "\n" (h: "ln -s aidev $out/bin/${h}") harnesses}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    for name in aidev ${lib.concatStringsSep " " harnesses}; do
      test -x "$out/bin/$name" || { echo "missing $name"; exit 1; }
    done
    grep -q 'AIDEV_RUNTIME_PATH="/nix/store' $out/bin/aidev

    runHook postInstallCheck
  '';

  meta = {
    description = "Run AI coding harnesses inside a per-project devcontainer";
    longDescription = ''
      Provides claude, codex, copilot and opencode wrappers that start (or
      reuse) a DevPod devcontainer anchored at the current git root and drop
      straight into that harness with permission prompts disabled.
    '';
    homepage = "https://github.com/EricKuck/ai-devcontainer";
    license = lib.licenses.mit;
    mainProgram = "aidev";
    platforms = lib.platforms.unix;
  };
}
