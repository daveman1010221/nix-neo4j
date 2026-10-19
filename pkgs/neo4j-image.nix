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

    # NEO4J_AUTH=neo4j/<password> sets the initial password, as the official image's entrypoint does, so the
    # first login is not the default neo4j/neo4j with a demand to change it. It fails closed: a value that is not
    # neo4j/<password>, or a password under Neo4j's minimum length of 8 (which also rules out "neo4j"), stops the
    # container with a message and never falls back to the default credentials. It is applied only while there is
    # no system database yet, which is the first start: after that the password is whatever it was changed to
    # (ALTER USER), and an environment variable must not quietly overwrite it, or fail on every restart.
    # Unset or empty does nothing. The password is never printed, and the variable is not passed on to the server.
    if [ -n "''${NEO4J_AUTH:-}" ]; then
      case "$NEO4J_AUTH" in
        neo4j/*) ;;
        *)
          echo "neo4j-entrypoint: NEO4J_AUTH must be neo4j/<password>; the only user is neo4j." >&2
          exit 1
          ;;
      esac
      neo4j_password="''${NEO4J_AUTH#neo4j/}"
      unset NEO4J_AUTH
      if [ "''${#neo4j_password}" -lt 8 ]; then
        echo "neo4j-entrypoint: the password in NEO4J_AUTH is shorter than Neo4j's minimum of 8 characters." >&2
        exit 1
      fi
      if [ -e "$NEO4J_DATA/databases/system" ] || [ -e "$NEO4J_DATA/transactions/system" ]; then
        echo "neo4j-entrypoint: the system database already exists, so NEO4J_AUTH is not applied (change the password with ALTER USER)." >&2
      else
        /opt/neo4j/bin/neo4j-admin dbms set-initial-password "$neo4j_password"
        echo "neo4j-entrypoint: the initial password was set from NEO4J_AUTH." >&2
      fi
      unset neo4j_password
    fi

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
