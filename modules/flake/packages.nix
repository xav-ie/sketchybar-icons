# The sketchybar-icons package (and the flake's default).
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.sketchybar-icons = pkgs.callPackage ../../package.nix { };
      packages.default = config.packages.sketchybar-icons;
    };
}
