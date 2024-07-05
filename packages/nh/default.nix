{
  stdenv,
  lib,
  rustPlatform,
  installShellFiles,
  makeBinaryWrapper,
  darwin,
  nvd,
  nix-output-monitor,
  figlet,
  lolcat,
  fetchFromGitHub,
}:
let
  runtimeDeps = [
    nvd
    nix-output-monitor
    figlet
    lolcat
  ];
in
rustPlatform.buildRustPackage {
  pname = "nh";
  version = "3.5.17-fork";

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "nh";
    rev = "9927f24e237369212b39240893343467c08cc2ff";
    hash = "sha256-mANnnRXF8WQhHmq5bxMThUj24Il6c0pssewh6U7LrH0=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

  doCheck = false; # faster builds

  preFixup = ''
    mkdir completions
    $out/bin/nh completions --shell bash > completions/nh.bash
    $out/bin/nh completions --shell zsh > completions/nh.zsh
    $out/bin/nh completions --shell fish > completions/nh.fish

    installShellCompletion completions/*
  '';

  postFixup = ''
    wrapProgram $out/bin/nh \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  cargoHash = "sha256-aNB2SMjj2ErrFPNeIozl9AB8645QQ1xed9e+8aRz8I0=";

  meta = {
    description = "Yet another nix cli helper";
    homepage = "https://github.com/viperML/nh";
    license = lib.licenses.eupl12;
    mainProgram = "nh";
    maintainers = with lib.maintainers; [
      drupol
      viperML
    ];
  };
}
