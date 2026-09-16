# pi from its npm release, independent of which nixpkgs a machine tracks
# (the Intel Mac is pinned to 26.05, whose pi predates the pi-ai exports that
# current extensions need).
#
# The tarball ships an npm-shrinkwrap.json that npm honours over any outer
# lockfile, so the shrinkwrap itself is vendored here as package-lock.json.
# To bump: set version below, then from the new tarball copy package.json
# (minus devDependencies, which the shrinkwrap does not carry) and
# npm-shrinkwrap.json (as package-lock.json) into this directory, fill in
# "integrity" for the @earendil-works entries that lack it (from
# `npm view <pkg>@<ver> dist.integrity`), and update `hash` from
# `nix-prefetch-url <tarball url>`.
{ lib, buildNpmPackage, fetchurl, importNpmLock, makeBinaryWrapper, ripgrep, fd, stdenvNoCC }:

buildNpmPackage (finalAttrs: {
  pname = "pi";
  version = "0.85.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${finalAttrs.version}.tgz";
    hash = "sha256-H0mHKWSb3OZH0RYJk7TZK/PGFMyBkhO+4vkd008qevQ=";
  };
  sourceRoot = "package";

  npmDeps = importNpmLock { npmRoot = ./.; };
  npmConfigHook = importNpmLock.npmConfigHook;

  postPatch = ''
    rm npm-shrinkwrap.json
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [ makeBinaryWrapper ];

  postInstall = lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    # Linux-only blobs that make audit-tmpdir try to patchelf on darwin
    rm -rf $out/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@anthropic-ai/sandbox-runtime/dist/vendor/seccomp \
           $out/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@anthropic-ai/sandbox-runtime/vendor/seccomp
  '';

  postFixup = ''
    wrapProgram $out/bin/pi --prefix PATH : ${lib.makeBinPath [ ripgrep fd ]}
  '';

  meta = {
    description = "Coding agent CLI (earendil-works/pi), packaged from its npm release";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
})
