{ lib, ... }:
{
  imports = lib.fileset.toList (
    lib.fileset.fileFilter (
      file: file.name != "default.nix" && file.name != "README.md" && file.name != "bridge.nix"
    ) ./.
  );
}
