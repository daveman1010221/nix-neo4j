{ lib
, pkgs
, buildMavenPackage
, fetchFromGitHub
, fetchurl
, jdk21_headless
, browserAssets ? null
, version ? "2025.8.0"
, upstreamRev ? "2025.08"
, srcHash ? lib.fakeHash
, mvnHash ? lib.fakeHash
}:

let
  src = fetchFromGitHub {
    owner = "neo4j";
    repo  = "neo4j";
    rev   = upstreamRev;
    hash  = srcHash;
  };

  browserJarVersion = version;

  manifestFile   = ./assets/neo4j-browser-MANIFEST.MF;
  pomPropsFile   = ./assets/neo4j-browser-pom.properties;
  pomXmlFile     = ./assets/neo4j-browser-pom.xml;
  neo4jConfFile  = ./assets/neo4j.conf;
  jvmConfFile    = ./assets/jvm.conf;

  browserJar = pkgs.runCommand "neo4j-browser-ce-${browserJarVersion}.jar"
    { buildInputs = [ jdk21_headless pkgs.zip ]; } ''
      set -eux

      stage="$TMPDIR/stage"
      mkdir -p \
        "$stage/browser" \
        "$stage/META-INF/maven/org.neo4j.client/neo4j-browser" \
        "$stage/META-INF"

      # 1) Static browser assets from our Nix-built dist
      cp -r ${browserAssets}/libexec/neo4j-browser/deps/neo4j-browser/dist/* "$stage/browser/"

      # 2) License / notice files from upstream repo root
      cp ${browserAssets.src}/LICENSE      "$stage/browser/LICENSE"
      cp ${browserAssets.src}/LICENSES.txt "$stage/browser/LICENSES.txt"
      cp ${browserAssets.src}/NOTICE.txt   "$stage/browser/NOTICE.txt"

      # 3) Manifest from asset file
      cp ${manifestFile} "$stage/META-INF/MANIFEST.MF"

      # 4) Maven metadata from asset templates (version substituted)
      sed "s/@BROWSER_VERSION@/${browserJarVersion}/g" \
        ${pomPropsFile} > \
        "$stage/META-INF/maven/org.neo4j.client/neo4j-browser/pom.properties"

      sed "s/@BROWSER_VERSION@/${browserJarVersion}/g" \
        ${pomXmlFile} > \
        "$stage/META-INF/maven/org.neo4j.client/neo4j-browser/pom.xml"

      # 5) Jar index
      {
        echo "JarIndex-Version: 1.0"
        echo
        echo "."
        (cd "$stage" && find browser META-INF -type f | sed 's|^\./||') || true
      } > "$stage/META-INF/INDEX.LIST"

      cd "$stage"
      ${jdk21_headless}/bin/jar cfm "$out" META-INF/MANIFEST.MF browser META-INF
    '';

in
buildMavenPackage {
  pname = "neo4j-community-src";
  inherit version src;
  nativeBuildInputs = [ jdk21_headless ];
  doCheck = false;

  mvnParameters = "-T1C -Drevision=${version} -Dgpg.skip=true -Dlicense.skip=true -Dstyle.color=never -DskipITs -DskipTests -Dmaven.test.skip=true -Djacoco.skip=true";
  inherit mvnHash;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/opt/neo4j

    TARBALL="$(find . -type f -name 'neo4j-community-*-unix.tar.gz' | head -n1 || true)"
    if [ -z "$TARBALL" ]; then
      echo "Could not find assembled neo4j community tarball" >&2
      echo "Check packaging modules under */packaging/*/target/." >&2
      exit 1
    fi
    tar -xzf "$TARBALL" --strip-components=1 -C "$out/opt/neo4j"

    install -Dm0644 ${browserJar} \
      "$out/opt/neo4j/lib/neo4j-browser-ce-${browserJarVersion}.jar"

    mkdir -p "$out/opt/neo4j/conf"
    install -Dm0644 ${neo4jConfFile} "$out/opt/neo4j/conf/neo4j.conf"
    install -Dm0644 ${jvmConfFile}   "$out/opt/neo4j/conf/jvm.conf"

    runHook postInstall
  '';
}
