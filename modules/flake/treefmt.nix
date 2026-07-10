# treefmt formatter configuration (`nix fmt` / `treefmt`). Wires the treefmt-nix
# flake module, which auto-populates `formatter` and `checks`.
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { system, ... }:
    {
      treefmt = {
        # Custom Nushell formatter module (treefmt-nix has no nufmt yet).
        imports = [
          (
            { mkFormatterModule, ... }:
            {
              imports = [
                (mkFormatterModule {
                  name = "nufmt";
                  mainProgram = "nufmt";
                  includes = [ "*.nu" ];
                })
              ];
            }
          )
        ];

        programs = {
          nixfmt.enable = true; # *.nix
          deadnix.enable = true; # prune dead nix
          statix.enable = true; # nix lints
          shfmt.enable = true; # *.sh (scripts/)
          prettier.enable = true; # *.md, *.yml (.github/)
          swift-format.enable = true; # *.swift
          nufmt = {
            enable = true; # *.nu (examples/)
            package = inputs.nufmt.packages.${system}.default;
          };
        };

        settings = {
          on-unmatched = "fatal";
          excludes = [
            "LICENSE"
            "flake.lock"
            ".gitignore"
            ".envrc"
            "*.png" # gallery/asset images
            "*.nuon" # data/config format (nufmt.nuon), no formatter
          ];
        };
      };
    };
}
