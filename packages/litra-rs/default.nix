{
  stdenv,
  lib,
  rustPlatform,
  installShellFiles,
  makeBinaryWrapper,
  darwin,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage {
  pname = "litra";
  version = "2.2.0-fork";

  src = fetchFromGitHub {
    owner = "EricKuck";
    repo = "litra-rs";
    rev = "9e079fc404d1";
    hash = "sha256-IFwf9Z4sfoXbQzxDPygrDmwq5byDATPqxqMLGBOOT08=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

  doCheck = false;

  cargoHash = "sha256-8g6YhwBgclNawnL8c0GDTT73TOS/+9UB1m2BOkz2ynU=";

  meta = {
    description = "Control your Logitech Litra light from the command line";
    homepage = "https://github.com/timrogers/litra-rs";
    mainProgram = "litra";
  };
}
