{
  lib,
  osConfig ? { },
  ...
}:
{
  # NEVER change this value after the initial install, for any reason,
  home.stateVersion = lib.mkDefault (osConfig.system.stateVersion or "23.11"); # Did you read the comment?
}
