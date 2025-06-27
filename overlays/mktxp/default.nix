{ ... }:

_final: prev: {
  mktxp = prev.mktxp.overrideAttrs (old: {
    src = prev.fetchFromGitHub {
      owner = "EricKuck";
      repo = "mktxp";
      rev = "e103a6729dffe92137ee13c4af585249fbb140e3";
      hash = "sha256-iswP0p+a4OTqv0oUjH8slHjG/RlzOLzJvA6SgcrcRXs=";
    };
  });
}
