{ lib }:

with lib;

rec {
  mkUniqueValueAttrSet =
    {
      name,
    }:
    {
      option = mkOption {
        type = types.attrs;
      };

      assertion =
        config:
        let
          values = attrValues (getAttrFromPath (splitString "." name) config);
          duplicates = unique (filter (v: count (x: x == v) values > 1) values);
        in
        {
          assertion = duplicates == [ ];
          message =
            if duplicates == [ ] then
              ""
            else
              "All values in `${name}` must be unique. Found duplicates: ${toString duplicates}";
        };
    };
}
