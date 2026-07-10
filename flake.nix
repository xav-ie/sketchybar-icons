{
  description = "Render native macOS Battery/Wi-Fi (and any SF Symbol) icons to PNG for sketchybar — no screen-recording aliases";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nufmt.url = "github:nushell/nufmt";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # macOS only (AppKit + CoreWLAN).
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      imports = [
        ./modules/flake/packages.nix
        ./modules/flake/treefmt.nix
        ./modules/flake/devshell.nix
      ];
    };
}
