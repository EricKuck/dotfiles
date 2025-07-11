{ lib, ... }:
{
  imports = lib.fileset.toList (lib.fileset.fileFilter (file: file.name != "default.nix") ./.);
}
