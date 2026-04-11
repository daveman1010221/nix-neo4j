{ pkgs, lib, neo4jTree }:

let
  jdk     = pkgs.jdk21_headless;
  locales = pkgs.glibcLocales;

  entrypoint = pkgs.writeShellScriptBin "neo4j-entrypoint" ''
    set -euo pipefail

    export JAVA_HOME="${jdk}"
    export PATH="$JAVA_HOME/bin:$PATH"

    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    export LOCALE_ARCHIVE="${locales}/lib/locale/locale-archive"

    export NEO4J_CONF=/var/lib/neo4j/conf
    export NEO4J_HOME=/opt/neo4j
    export NEO4J_LOGS=/var/lib/neo4j/logs
    export NEO4J_DATA=/var/lib/neo4j/data
    export NEO4J_PLUGINS=/var/lib/neo4j/plugins
    export NEO4J_IMPORT=/var/lib/neo4j/import
    export NEO4J_RUN=/var/lib/neo4j/run

    umask 002

    # Be nice and ensure ownership at runtime as well
    chown -R 7474:7474 /opt/neo4j || true

    /opt/neo4j/bin/neo4j-admin server validate-config || true

    # In neo4j-entrypoint, before exec:
    rm -f /var/lib/neo4j/conf/truststore.jks
    $JAVA_HOME/bin/keytool -import \
        -noprompt \
        -alias polar-neo4j-ca \
        -file /var/lib/neo4j/certificates/https/trusted/ca.pem \
        -keystore /var/lib/neo4j/conf/truststore.jks \
        -storepass changeit 2>/dev/null || true

    exec /opt/neo4j/bin/neo4j console
  '';

in
pkgs.dockerTools.buildLayeredImage {
  name = "nix-neo4j";
  tag  = "latest";

  extraCommands = ''
    mkdir -p etc
    install -m0644 ${./assets/etc-passwd}        etc/passwd
    install -m0644 ${./assets/etc-group}         etc/group
    install -m0644 ${./assets/etc-nsswitch.conf} etc/nsswitch.conf
  '';

  contents = pkgs.buildEnv {
    name = "neo4j-rootfs";
    paths = [
      neo4jTree
      jdk
      locales
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.which
      entrypoint
    ];
    pathsToLink = [ "/bin" "/opt" "/etc/ssl" ];
  };

  config = {
    User = "7474:7474";
    WorkingDir = "/opt/neo4j/data";

    ExposedPorts = {
      "7474/tcp" = {};
      "7687/tcp" = {};
    };

    Volumes = {
      "/opt/neo4j/data"    = {};
      "/opt/neo4j/logs"    = {};
      "/opt/neo4j/plugins" = {};
      "/opt/neo4j/conf"    = {};
    };

    Env = [
      "LANG=en_US.UTF-8"
      "LC_ALL=en_US.UTF-8"
      "LOCALE_ARCHIVE=${locales}/lib/locale/locale-archive"
      "HOME=/opt/neo4j"
      "NEO4J_CONF=/var/lib/neo4j/conf"
    ];

    Entrypoint = [ "${entrypoint}/bin/neo4j-entrypoint" ];
  };
}
