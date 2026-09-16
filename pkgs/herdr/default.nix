# herdr from its release binaries: Homebrew has no bottle for the Intel Mac's
# macOS (Tier 3) and nixpkgs-26.05 has no herdr for x86_64-darwin.
# Bump: version + hashes from `nix-prefetch-url <url>` (nix hash convert --to sri).
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.9.0";
  arch = if stdenvNoCC.hostPlatform.isAarch64 then "aarch64" else "x86_64";
  os = if stdenvNoCC.hostPlatform.isDarwin then "macos" else "linux";
  hashes = {
    "macos-x86_64" = "sha256-0MkgsqEmp0gJ+hSRQRyaCXpEeGysnCylG4GKmVWBzxY=";
    "macos-aarch64" = "sha256-MrU98JhyYoBZx4mmnwKmuOKeFN3yZxFCHzRj9wwa7xc=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;
  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-${os}-${arch}";
    hash = hashes."${os}-${arch}";
  };
  dontUnpack = true;
  installPhase = ''
    install -Dm755 $src $out/bin/herdr
  '';
  meta = {
    description = "Terminal workspace manager for AI coding agents";
    homepage = "https://herdr.dev";
    license = lib.licenses.agpl3Plus;
    mainProgram = "herdr";
  };
}
