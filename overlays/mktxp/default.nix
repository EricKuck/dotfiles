{ ... }:

_final: prev: {
  mktxp = prev.mktxp.overridePythonAttrs (old: {
    src = prev.fetchFromGitHub {
      owner = "EricKuck";
      repo = "mktxp";
      rev = "a7c1a14371de971e61355f063e3f81f4856b6eb3";
      hash = "sha256-tnYEsfjGCDTZCH3AwSWNrFBgG77ms0O6ZPJN0yUfPhI=";
    };

    dependencies = old.dependencies ++ [
      prev.python3Packages.pyyaml
    ];
  });
}
