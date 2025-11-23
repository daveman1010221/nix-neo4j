{ pkgs, lib, neo4jTree }:

let
  jdk     = pkgs.jdk21_headless;
  locales = pkgs.glibcLocales;

  baseEtc = pkgs.runCommand "base-etc" {} ''
    mkdir -p "$out/etc"

    install -Dm0644 ${./assets/etc-passwd}        "$out/etc/passwd"
    install -Dm0644 ${./assets/etc-group}         "$out/etc/group"
    install -Dm0644 ${./assets/etc-nsswitch.conf} "$out/etc/nsswitch.conf"

    touch "$out/.keep"
  '';

  entrypoint = pkgs.writeShellScriptBin "neo4j-entrypoint" ''
    set -euo pipefail

    export JAVA_HOME="${jdk}"
    export PATH="$JAVA_HOME/bin:$PATH"

    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    export LOCALE_ARCHIVE="${locales}/lib/locale/locale-archive"

    export HOME="/opt/neo4j"
    umask 002

    # Be nice and ensure ownership at runtime as well
    chown -R 7474:7474 /opt/neo4j || true

    /opt/neo4j/bin/neo4j-admin server validate-config || true
    exec /opt/neo4j/bin/neo4j console
  '';

in
pkgs.dockerTools.buildImage {
  name = "nix-neo4j";
  tag  = "latest";

  copyToRoot = pkgs.buildEnv {
    name = "neo4j-rootfs";
    paths = [
      neo4jTree
      baseEtc
      jdk
      locales
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.which
      entrypoint
    ];
    pathsToLink = [ "/bin" "/opt" "/etc" ];
  };

  runAsRoot = ''
    #!${pkgs.runtimeShell}
    mkdir -p $root/opt/neo4j/data \
             $root/opt/neo4j/logs \
             $root/opt/neo4j/run  \
             $root/opt/neo4j/import \
             $root/opt/neo4j/plugins \
             $root/opt/neo4j/conf

    chown -R 7474:7474 \
      $root/opt/neo4j/data \
      $root/opt/neo4j/logs \
      $root/opt/neo4j/run  \
      $root/opt/neo4j/import \
      $root/opt/neo4j/plugins

    chmod -R u+rwX,g+rwX $root/opt/neo4j
  '';

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
    ];

    Entrypoint = [ "${entrypoint}/bin/neo4j-entrypoint" ];
  };
}
