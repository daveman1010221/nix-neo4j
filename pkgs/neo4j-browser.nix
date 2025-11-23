{ lib, pkgs, ... }:

let
  version = "2025.8.0";

  # Upstream Neo4j Browser sources (no patches)
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "neo4j";
    repo  = "neo4j-browser";
    rev   = version;
    hash  = "sha256-ngGGoiJwafT3i5gYiYKEI1MymJQdTn3/RhmJ8R2j66M=";
  };

  yarnLockFile = ./neo4j-browser-yarn.lock;

  node = pkgs.nodejs_20;
in
pkgs.mkYarnPackage {
  pname = "neo4j-browser";
  inherit version;

  # use upstream sources so neo4j-from-source can still use ${browserAssets.src}
  src         = upstreamSrc;
  packageJSON = "${upstreamSrc}/package.json";
  yarnLock    = yarnLockFile;

  offlineCache = pkgs.fetchYarnDeps {
    yarnLock = yarnLockFile;
    sha256 = "sha256-6ufXfvmdODdrHTMCitmkzewYoD0Xkw1+I9D05bpOk9Y=";
  };

  nodejs = node;

  buildPhase = ''
    set -eux
    export HOME="$TMPDIR"
    export NODE_ENV=production
    export PATH=${node}/bin:"$PATH"
    export NODE_OPTIONS=--openssl-legacy-provider

    # Sanity check before patch
    echo "=== word-color before patch ==="
    grep -n "word-color-calculator" node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js || true

    # NOTE: Upstream includes nullish-coalescing; remove once support lands in node 20 build chain.
    substituteInPlace node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js --replace " ?? " " || "

    echo "=== word-color after patch ==="
    grep -n "word-color-calculator" node_modules/@neo4j-devtools/word-color/dist/src/word-color-calculator.js || true

    yarn --offline --frozen-lockfile --non-interactive build
  '';

  meta = with lib; {
    description = "Neo4j Browser UI static assets (built from upstream sources)";
    homepage    = "https://github.com/neo4j/neo4j-browser";
    license     = licenses.asl20;
    platforms   = platforms.linux;
  };
}
