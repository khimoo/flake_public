{
  flakeRef,
  optionsFile,
}:
let
  flake = builtins.getFlake flakeRef;
  inherit (flake.inputs.nixpkgs) lib;
  wanted = builtins.fromJSON (builtins.readFile optionsFile);

  # show turns a value into JSON-safe data. Derivations, paths and functions become marked
  # objects, and the depth and size limits keep a reference into a package set from walking it all.
  show =
    depth: v:
    let
      t = builtins.tryEval v;
      x = t.value;
    in
    if !t.success then
      { "$error" = true; }
    else if lib.isDerivation x then
      let
        out = builtins.tryEval x.outPath;
      in
      { "$drv" = if out.success then builtins.unsafeDiscardStringContext out.value else x.name or "?"; }
    else if builtins.isFunction x then
      { "$function" = true; }
    # toJSON calls __toString and reads outPath, so these sets must not be walked attribute by
    # attribute (the walk would replace __toString with a non-function). Home Manager's gvariant
    # values are such sets.
    else if builtins.isAttrs x && x ? __toString then
      let
        s = builtins.tryEval (toString x);
      in
      if s.success then builtins.unsafeDiscardStringContext s.value else { "$error" = true; }
    else if builtins.isAttrs x && x ? outPath then
      show (depth + 1) x.outPath
    else if builtins.isPath x then
      { "$path" = toString x; }
    else if builtins.isString x then
      builtins.unsafeDiscardStringContext x
    else if depth > 12 then
      { "$deep" = true; }
    else if builtins.isList x then
      map (show (depth + 1)) x
    else if builtins.isAttrs x then
      if builtins.length (builtins.attrNames x) > 500 then
        { "$large" = builtins.length (builtins.attrNames x); }
      else
        lib.mapAttrs (_: show (depth + 1)) x
    else
      x;

  missing = {
    "$missing" = true;
  };
  values = root: pairs: builtins.listToAttrs (map (p: lib.nameValuePair p.display (show 0 (lib.attrByPath p.parts missing root))) pairs);

  # An element can write below an option, such as programs.git.settings.init.defaultBranch inside
  # the programs.git.settings option, so the declaration is that of the longest prefix that is an option.
  declaration =
    opts: parts:
    let
      prefixes = lib.reverseList (lib.genList (n: lib.take (n + 1) parts) (builtins.length parts));
      found = lib.findFirst (p: lib.isOption (lib.attrByPath p null opts)) null prefixes;
    in
    if found == null then
      null
    else
      {
        option = lib.concatStringsSep "." found;
        positions = map (d: {
          file = builtins.unsafeDiscardStringContext (toString d.file);
          inherit (d) line;
        }) ((lib.attrByPath found null opts).declarationPositions or [ ]);
      };
  declarations = opts: pairs: builtins.listToAttrs (map (p: lib.nameValuePair p.display (declaration opts p.parts)) pairs);
  finalForHost =
    host: want:
    if !(flake.nixosConfigurations ? ${host}) then
      throw "Unknown NixOS host: ${host}"
    else
    let
      inherit (flake.nixosConfigurations.${host}) config options;
      homeUsers = config.home-manager.users or { };
    in
    {
      nixos = values config want.nixos;
      users = lib.mapAttrs (
        user: pairs:
        if homeUsers ? ${user} then values homeUsers.${user} pairs else null
      ) want.users;
      declarations = {
        nixos = declarations options want.nixos;
        users = lib.mapAttrs (
          user: pairs:
          if homeUsers ? ${user} then
            declarations options.home-manager.users.valueMeta.attrs.${user}.configuration.options pairs
          else
            null
        ) want.users;
      };
    };
in
lib.mapAttrs finalForHost wanted
