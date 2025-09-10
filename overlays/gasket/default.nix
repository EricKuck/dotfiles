{ ... }:

_final: prev: {
  linuxPackages_6_16 = prev.linuxPackages_6_16.extend (
    finalPkgs: oldPkgs: {
      gasket = oldPkgs.gasket.overrideAttrs (old: rec {
        patches = [
          (_final.fetchpatch2 {
            # https://github.com/google/gasket-driver/issues/39
            # https://github.com/google/gasket-driver/pull/50
            name = "linux-6.15-compat.patch";
            url = "https://github.com/google/gasket-driver/pull/50.patch";
            hash = "sha256-B3hT1x5p7dX4Plwcr21QltA3XGu4dn6GduXPmneDTps=";
          })
        ];
      });
    }
  );
}
