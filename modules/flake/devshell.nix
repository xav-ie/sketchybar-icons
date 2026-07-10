# `nix develop` shell (auto-loaded via .envrc/direnv) with the tooling to
# regenerate the README gallery (scripts/render-gallery.sh): the sketchybar-icons
# binary, ImageMagick to montage the tiles, and oxipng to losslessly optimise the
# output PNGs.
{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.packages.sketchybar-icons
          pkgs.imagemagick
          pkgs.oxipng
        ];
      };
    };
}
