#!/usr/bin/env bash
# tests/auth.sh -- NEO4J_AUTH in the nix-built image's entrypoint (pkgs/neo4j-image.nix).
#
# Runs the built image under podman, each case with a throwaway password and an empty data directory, and checks
# what Neo4j accepts. Needs podman and curl; no cluster.
#
#   nix build -L .#neo4j-image -o result-neo4j-image
#   tests/auth.sh [path to the image archive, default result-neo4j-image]
#
# The cases:
#   1  first start: the NEO4J_AUTH password is accepted, the default neo4j/neo4j is not (401), the password is not
#      in the container's output
#   2  a restart on the same data: the password is kept, and the entrypoint says it did not apply it again
#   3  a restart with a different NEO4J_AUTH: the password the database has is not overwritten
#   4  NEO4J_AUTH that is not neo4j/<password>: the container stops with a message
#   5  a password shorter than 8 characters: the container stops with a message
#   6  NEO4J_AUTH unset: the default credentials, which must be changed. Neo4j answers them with HTTP 200 and
#      Neo.ClientError.Security.CredentialsExpired in the body (a wrong password is the 401), as before
set -uo pipefail

cd "$(dirname "$0")/.."
ARCHIVE="${1:-result-neo4j-image}"
PORT_BASE=$((20000 + RANDOM % 20000))
WORK=$(mktemp -d)
FAILED=0
CONTAINERS=()

cleanup() {
  for c in "${CONTAINERS[@]}"; do podman rm -f "$c" >/dev/null 2>&1; done
  rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "  pass  $1"; }
fail() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }
check() { # check "<description>" <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

echo "loading $ARCHIVE"
IMAGE=$(podman load -q -i "$ARCHIVE" | sed -n 's/^Loaded image: //p; s/^Loaded image(s): //p' | head -1)
[ -n "$IMAGE" ] || { echo "could not load the image"; exit 2; }
echo "image: $IMAGE"

# A Neo4j home with the directories the entrypoint expects, writable by the image's user (7474), and the least
# configuration that makes it listen: the chart provides the real one at run time. The directories must be set in
# the configuration as the cluster's neo4j.conf sets them: Neo4j takes them from there, not from the NEO4J_DATA
# variable the entrypoint exports, and without them the data would go to /opt/neo4j, which the image's user cannot
# write.
new_home() {
  local d="$WORK/$1"
  mkdir -p "$d"/{conf,data,logs,plugins,import,run}
  cat > "$d/conf/neo4j.conf" <<'CONF'
server.default_listen_address=0.0.0.0
server.http.enabled=true
server.bolt.enabled=true
server.directories.data=/var/lib/neo4j/data
server.directories.import=/var/lib/neo4j/import
server.directories.logs=/var/lib/neo4j/logs
server.directories.plugins=/var/lib/neo4j/plugins
server.directories.run=/var/lib/neo4j/run
CONF
  echo "$d"
}

# start <name> <home> <port> [env args...]; echoes the container name
start() {
  local name="$1" home="$2" port="$3"; shift 3
  CONTAINERS+=("$name")
  # --tmpfs /tmp: the image has no /tmp and Neo4j's JNA needs one; the chart mounts an emptyDir there.
  # --log-driver=k8s-file: `podman logs` reads the container's output back, and with the journald driver (a common
  # default) it can return nothing, which would fail every check that reads the entrypoint's messages.
  podman run -d --name "$name" --userns=keep-id:uid=7474,gid=7474 --tmpfs /tmp:rw,mode=1777 --log-driver=k8s-file \
    -v "$home:/var/lib/neo4j" -p "$port:7474" "$@" "$IMAGE" >/dev/null
}

wait_up() { # wait_up <port> : up when the HTTP port answers
  for _ in $(seq 1 60); do
    [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/")" = "200" ] && return 0
    sleep 3
  done
  return 1
}

# code <port> <password> : the HTTP status of a trivial authenticated query as neo4j; the body goes to $WORK/body
code() {
  curl -s -m 8 -o "$WORK/body" -w '%{http_code}' -u "neo4j:$2" -H 'Content-Type: application/json' \
    -d '{"statements":[{"statement":"RETURN 1"}]}' "http://127.0.0.1:$1/db/neo4j/tx/commit"
}

stopped_with_message() { # <container> <text>: it is not running, it exited non-zero, and said <text>
  for _ in $(seq 1 20); do
    [ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "false" ] && break
    sleep 1
  done
  [ "$(podman inspect -f '{{.State.Running}}' "$1")" = "false" ] \
    && [ "$(podman inspect -f '{{.State.ExitCode}}' "$1")" != "0" ] \
    && podman logs "$1" 2>&1 | grep -q "$2"
}

PW="Throwaway-$RANDOM-pw$RANDOM"
PW2="Another-$RANDOM-pw$RANDOM"

echo "case 1: first start"
H1=$(new_home one); P1=$((PORT_BASE + 1))
start t-one "$H1" "$P1" -e "NEO4J_AUTH=neo4j/$PW"
if wait_up "$P1"; then
  check "the NEO4J_AUTH password is accepted (200)" test "$(code "$P1" "$PW")" = "200"
  check "the default neo4j/neo4j is rejected (401), not a demand to change it" test "$(code "$P1" neo4j)" = "401"
  check "the container's output says the password was set" bash -c "podman logs t-one 2>&1 | grep -q 'initial password was set'"
  check "the password is nowhere in the container's output" bash -c "! podman logs t-one 2>&1 | grep -qF '$PW'"
else
  fail "neo4j did not come up on a first start"
fi

echo "case 2: a restart on the same data"
podman stop -t 20 t-one >/dev/null 2>&1; podman rm -f t-one >/dev/null 2>&1
start t-two "$H1" "$P1" -e "NEO4J_AUTH=neo4j/$PW"
if wait_up "$P1"; then
  check "the password is kept (200)" test "$(code "$P1" "$PW")" = "200"
  check "it says it did not apply NEO4J_AUTH again" bash -c "podman logs t-two 2>&1 | grep -q 'NEO4J_AUTH is not applied'"
else
  fail "neo4j did not come up on a restart"
fi

echo "case 3: a restart with a different NEO4J_AUTH"
podman stop -t 20 t-two >/dev/null 2>&1; podman rm -f t-two >/dev/null 2>&1
start t-three "$H1" "$P1" -e "NEO4J_AUTH=neo4j/$PW2"
if wait_up "$P1"; then
  check "the password the database has is not overwritten (the old one still works)" test "$(code "$P1" "$PW")" = "200"
  check "the new one is not accepted (401)" test "$(code "$P1" "$PW2")" = "401"
else
  fail "neo4j did not come up with a different NEO4J_AUTH on existing data"
fi

echo "case 4: NEO4J_AUTH that is not neo4j/<password>"
H4=$(new_home four)
start t-four "$H4" $((PORT_BASE + 4)) -e "NEO4J_AUTH=admin/$PW"
check "the container stops with a message" stopped_with_message t-four "NEO4J_AUTH must be neo4j/<password>"

echo "case 5: a password under 8 characters"
H5=$(new_home five)
start t-five "$H5" $((PORT_BASE + 5)) -e "NEO4J_AUTH=neo4j/short"
check "the container stops with a message" stopped_with_message t-five "shorter than Neo4j's minimum"

echo "case 6: NEO4J_AUTH unset"
H6=$(new_home six); P6=$((PORT_BASE + 6))
start t-six "$H6" "$P6"
if wait_up "$P6"; then
  # Observed, not assumed: the default credentials are valid but expired, which the query API reports as a 200
  # whose body carries CredentialsExpired; only a wrong password is a 401.
  check "the default neo4j/neo4j is valid but must be changed: 200 with CredentialsExpired in the body" \
    bash -c "[ \"\$(curl -s -m 8 -o '$WORK/b6' -w '%{http_code}' -u neo4j:neo4j -H 'Content-Type: application/json' -d '{\"statements\":[{\"statement\":\"RETURN 1\"}]}' http://127.0.0.1:$P6/db/neo4j/tx/commit)\" = 200 ] && grep -q CredentialsExpired '$WORK/b6'"
  check "a wrong password is still a 401" test "$(code "$P6" "not-the-password-$RANDOM")" = "401"
else
  fail "neo4j did not come up with NEO4J_AUTH unset"
fi

echo
if [ "$FAILED" -eq 0 ]; then echo "all passed"; else echo "$FAILED failed"; exit 1; fi
