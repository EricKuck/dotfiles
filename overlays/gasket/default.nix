{ ... }:

_final: prev: {
  linuxPackages_6_13 = prev.linuxPackages_6_13.extend (
    finalPkgs: oldPkgs: {
      gasket = oldPkgs.gasket.overrideAttrs (old: rec {
        patches = old.patches ++ [
          (_final.fetchpatch2 {
            # https://github.com/google/gasket-driver/issues/39
            # https://github.com/google/gasket-driver/pull/40
            name = "linux-6.13-compat.patch";
            url = "https://github.com/google/gasket-driver/commit/6fbf8f8f8bcbc0ac9c9bef7a56f495a2c9872652.patch";
            hash = "sha256-roCo0/ETWuDVtZfbpFbrmy/icNI12A/ozOGQNLTtBUs=";
          })
        ];
      });
    }
  );
}
