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
    rev = "b64cc4d88f3a";
    hash = "sha256-pFxUCxjNlpyrvlFw55a8PPAvnlw8tkAIEW4kPToqbw8=";
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

  cargoHash = "sha256-WpvcuCJNL40hOe7WI0rUOE2S8BdZDNGx7SaTWyw9++c=";

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
