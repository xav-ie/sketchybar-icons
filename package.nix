{
  stdenv,
  swift,
}:
# Renders Apple's own SF Symbols to PNGs (and reads live Wi-Fi signal via
# CoreWLAN) so sketchybar can draw native Battery/Wi-Fi icons instead of
# screen-recording the real Control Center items via `alias`. AppKit and
# CoreWLAN auto-link on `import` under swiftc on darwin.
stdenv.mkDerivation {
  pname = "sketchybar-icons";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O *.swift -o sketchybar-icons
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp sketchybar-icons $out/bin/sketchybar-icons
    runHook postInstall
  '';
  meta.mainProgram = "sketchybar-icons";
}
