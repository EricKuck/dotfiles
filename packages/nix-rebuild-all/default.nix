{
  writeShellApplication,
  stdenv,
  jq,
  inputs,
}:

writeShellApplication {
  name = "nix-rebuild-all";
  runtimeInputs = [
    jq
    inputs.rex.packages.${stdenv.hostPlatform.system}.rex
  ];
  text = ''
    REMOTE_SCRIPT=${./remote.sh}
  ''
  + builtins.readFile ./nix-rebuild-all.sh;
}
