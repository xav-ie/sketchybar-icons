# The sketchybar-icons package (and the flake's default), plus the gallery
# renderer as a runnable app (`nix run .#render-gallery`).
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.sketchybar-icons = pkgs.callPackage ../../package.nix { };
      packages.default = config.packages.sketchybar-icons;

      # Regenerate the README gallery montages. Bundles its runtime deps so it
      # runs with a plain `nix run .#render-gallery [assets-dir]` — no devShell.
      packages.render-gallery = pkgs.writeShellApplication {
        name = "render-gallery";
        runtimeInputs = [
          config.packages.sketchybar-icons
          pkgs.imagemagick
          pkgs.oxipng
        ];
        text = builtins.readFile ../../scripts/render-gallery.sh;
      };

      # Validate the gallery renders cleanly: run the SAME render-gallery the
      # auto-commit Gallery workflow uses, then assert every expected montage is
      # a valid, non-empty PNG. Runs under `nix flake check` (and directly via
      # `nix build .#checks.<system>.gallery`), so a dev catches a broken
      # renderer locally instead of waiting on CI.
      #
      # It deliberately does NOT byte-compare against the committed assets/: SF
      # Symbol glyphs vary by macOS version, so a strict diff would false-positive
      # when run on a different macOS than CI. Keeping assets/ canonical is the
      # auto-commit workflow's job (it renders on the pinned macos-14 runner).
      #
      # `__noChroot` because SF Symbol rendering needs the host's system fonts,
      # which are unreachable in the sandbox.
      checks.gallery =
        pkgs.runCommand "gallery-check"
          {
            __noChroot = true;
            nativeBuildInputs = [
              config.packages.render-gallery
              pkgs.imagemagick
            ];
          }
          ''
            render-gallery "$PWD/rendered" >/dev/null
            fail=0
            for name in battery-discharging battery-charging battery-lowpower wifi clock system app-icon; do
              f="$PWD/rendered/$name.png"
              if [ ! -s "$f" ] || [ "$(magick identify -format '%m' "$f" 2>/dev/null)" != "PNG" ]; then
                echo "gallery: $name.png missing or not a valid PNG" >&2
                fail=1
              fi
            done
            [ "$fail" -eq 0 ] || exit 1
            echo "Gallery renders cleanly (7 montages)."
            touch "$out"
          '';
    };
}
