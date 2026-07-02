{
  description = "Render native macOS Battery/Wi-Fi (and any SF Symbol) icons to PNG for sketchybar — no screen-recording aliases";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # macOS only (AppKit + CoreWLAN).
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forSystems (pkgs: rec {
        sketchybar-icons = pkgs.callPackage ./package.nix { };
        default = sketchybar-icons;
      });

      formatter = forSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
