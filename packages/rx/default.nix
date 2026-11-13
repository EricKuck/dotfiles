{
  writeShellApplication,
  symlinkJoin,
  stdenv,
  git,
  gh,
  jq,
  inputs,
}:

let
  rex = inputs.rex.packages.${stdenv.hostPlatform.system}.rex;

  rx = writeShellApplication {
    name = "rx";
    runtimeInputs = [
      git
      jq
      rex
    ];
    text = builtins.readFile ./rx.sh;
  };

  wt = writeShellApplication {
    name = "wt";
    runtimeInputs = [
      git
      gh
      jq
      rex
      rx
    ];
    text = builtins.readFile ./wt.sh;
  };
in
symlinkJoin {
  name = "rx";
  paths = [
    rx
    wt
  ];
  postBuild = ''
    install -Dm644 ${./wt.fish} $out/share/fish/vendor_completions.d/wt.fish
  '';
}
