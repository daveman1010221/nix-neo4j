# pkgs/neo4j-browser.nix
{ lib, pkgs, ... }:

let
  version = "2025.8.0";

  node = pkgs.nodejs_22;

  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "neo4j";
    repo  = "neo4j-browser";
    rev   = version;
    hash  = "sha256-ngGGoiJwafT3i5gYiYKEI1MymJQdTn3/RhmJ8R2j66M=";
  };

  yarnLockFile = ./neo4j-browser-yarn.lock;

  offlineCache = pkgs.fetchYarnDeps {
    yarnLock = yarnLockFile;
    sha256 = "sha256-6ufXfvmdODdrHTMCitmkzewYoD0Xkw1+I9D05bpOk9Y=";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "neo4j-browser";
  inherit version;

  src = upstreamSrc;

  nativeBuildInputs = [
    node
    pkgs.yarn
    pkgs.yarnConfigHook
    pkgs.yarnBuildHook
    pkgs.yarnInstallHook
  ];

  inherit offlineCache;

  # yarnInstallHook installs to $out/libexec by default — preserve that
  # so neo4j-from-source.nix's ${browserAssets}/libexec/... path still works.
  yarnBuildScript = "build";

  # The .src passthrough so neo4j-from-source.nix can still do ${browserAssets.src}
  passthru.src = upstreamSrc;

  preBuild = ''
    export NODE_ENV=production
    export NODE_OPTIONS=--openssl-legacy-provider

    echo "=== word-color before patch ==="
    grep -n "word-color-calculator" node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js || true

    substituteInPlace node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js \
      --replace " ?? " " || "

    echo "=== word-color after patch ==="
    grep -n "word-color-calculator" node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js || true
  '';

  meta = with lib; {
    description = "Neo4j Browser UI static assets (built from upstream sources)";
    homepage    = "https://github.com/neo4j/neo4j-browser";
    license     = licenses.asl20;
    platforms   = platforms.linux;
  };
}
