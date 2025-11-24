# nix-neo4j

Build **Neo4j Community Edition from source using Nix**, including:

- A full Maven-driven server build (`neo4j-tree`)
- A fully Nix-built Browser UI (`neo4j-browser`)
- A reproducible OCI container image (`neo4j-image`)

---

## Features

- Builds **Neo4j Community**
- Builds the **Neo4j Browser UI** using Node 20
- Ships clean config files (`neo4j.conf`, `jvm.conf`)
- Produces a **minimal OCI image**, without excessive environment feature flags

---

## Directory Structure

```
pkgs/
  neo4j-browser.nix           # Builds Browser UI from source
  neo4j-from-source.nix       # Builds Neo4j server from source + merges Browser JAR
  neo4j-image.nix             # Builds final OCI image
  assets/                     # All config + manifest templates
```

Create the following local, dev/runtime dirs for mount points:

```
neo4j_data/       neo4j_logs/        neo4j_plugins/
neo4j_import/     neo4j_tmp/         neo4j_conf/
```

---

## Requirements

- Nix 2.20+
- Flakes enabled
- Podman or some other container runtime (for loading the final image)

---

## Quick Start

Build everything:

```sh
nix build -L .#neo4j-browser -o result-neo4j-browser
nix build -L .#neo4j-tree    -o result-neo4j-tree
nix build -L .#neo4j-image   -o result-neo4j-image
```

You can also just build `neo4j-image`, which will build the intermediate targets.

Then load the container:

```sh
podman load -i result-neo4j-image
```

Run it:

```sh
podman run -it --rm \
  -p 7474:7474 -p 7687:7687 \
  -v $PWD/neo4j_data:/opt/neo4j/data \
  -v $PWD/neo4j_logs:/opt/neo4j/logs \
  -v $PWD/neo4j_plugins:/opt/neo4j/plugins \
  -v $PWD/neo4j_conf:/opt/neo4j/conf \
  nix-neo4j:latest
```

Open Neo4j Browser at:

```
http://localhost:7474
```

---

## Overriding Neo4j Version / Upstream Rev

Edit `flake.nix`:

```nix
neo4jTree = pkgs.callPackage ./pkgs/neo4j-from-source.nix {
  inherit buildMavenPackage browserAssets;
  srcHash = "...";   # a valid hash update is provided upon first failed build of this dep
  mvnHash = "...";   # a valid hash update is provided upon first failed build of this dep
  version = "2025.8.0";
  upstreamRev = "2025.08";
};
```

### Get correct hashes

Run:

```sh
nix build -L .#neo4j-tree
```

Because you intentionally use `lib.fakeHash`, the build will fail immediately and Nix will print the required SRI.
Paste the hash back into `flake.nix` and rebuild.

---

## Overriding Browser Version

To update the Browser UI to a newer upstream release, you must regenerate the
Yarn lockfile and rebuild the offline dependency cache. The process looks like:

1. Clone the upstream Neo4j Browser repo:

   ```sh
   git clone https://github.com/neo4j/neo4j-browser.git
   cd neo4j-browser
   ```

2. Check out the tag you want:

   ```sh
   git checkout <version>
   ```

3. Ensure dependencies resolve cleanly and lockfile is stable:

   ```sh
   yarn install --immutable
   ```

4. Copy the resulting `yarn.lock` into this repository as:

   ```
   pkgs/neo4j-browser-yarn.lock
   ```

5. Update the `version` and `hash` in `pkgs/neo4j-browser.nix` to match the
   upstream tag you checked out and rehashed.

After that, continue with the steps below to regenerate the Nix offline cache.

Change `version` in `pkgs/neo4j-browser.nix` and update the upstream tag + hash.

Then regenerate yarn deps:

```sh
cd pkgs
yarn install --immutable
yarn list > /dev/null # sanity check
```

Then compute new yarn deps hash, after the build fails the first time.

Paste into:

```nix
offlineCache = pkgs.fetchYarnDeps {
  yarnLock = yarnLockFile;
  sha256 = "...";
};
```

---

## Why?

We needed a transparent container build, from source, with known dependencies, upon which we could customize the base image, in a repeatable manner, separating configuration from runtime state.

---

## License

MIT (for this repo).

Neo4j and Neo4j Browser follow their respective upstream licenses.
