{ ... }:

_final: prev: {
  tailscale = prev.tailscale.overrideAttrs (old: {
    doCheck = false;
  });
}
