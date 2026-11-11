{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "rex-guard";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Read-only filtering proxy for the Rex control socket";
    longDescription = ''
      Listens on its own unix socket and relays to the real Rex control socket,
      forwarding only an allow-list of read and layout methods. It gives a
      sandboxed agent `rex capture` and session inspection without the ability
      to spawn blocks or type into existing ones.
    '';
    mainProgram = "rex-guard";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
