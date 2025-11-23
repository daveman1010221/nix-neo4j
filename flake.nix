{
  description = "Nix-built Neo4j from source -> OCI image (no baked creds)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        buildMavenPackage =
          pkgs.callPackage "${nixpkgs}/pkgs/by-name/ma/maven/build-maven-package.nix" {};
      in f { inherit pkgs buildMavenPackage system; }
    );
  in {
    packages = forAllSystems ({ pkgs, buildMavenPackage, system, ... }:
      let
        browserAssets = pkgs.callPackage ./pkgs/neo4j-browser.nix { };

        neo4jTree = pkgs.callPackage ./pkgs/neo4j-from-source.nix {
          inherit buildMavenPackage browserAssets;

          # replace these two after first build error prints real SRIs
          srcHash = "sha256-+XzpIVl310RKB92mlQLDwC6dSLqnODk6MrCNBqdxZ0M=";
          mvnHash = "sha256-WAj2YizhAKKYKKwyf9V157Dd92yGylOJTIpsdE4vWc4=";
        };

      in {
        neo4j-browser = browserAssets;
        neo4j-tree    = neo4jTree;

        neo4j-image = pkgs.callPackage ./pkgs/neo4j-image.nix {
          neo4jTree = neo4jTree;
        };

        default       = self.packages.${system}.neo4j-image;
      });

    formatter = forAllSystems ({ pkgs, ... }: pkgs.alejandra);

    devShells = forAllSystems ({ pkgs, ... }: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          jdk21_headless
          maven
          git curl jq gnutar gzip coreutils which
          podman skopeo
          alejandra
        ];
        shellHook = ''
          export NEO4J_VERSION="${NEO4J_VERSION:-5.26.0}"
          echo "neo4j-dev ready. To pin hashes:"
          echo "  1) nix build -L .#neo4j-tree
          echo "  2) paste both into flake.nix call"
          echo "  3) nix build -L .#neo4j-image && podman load -i result"
          nix build -L .#neo4j-browser -o result-neo4j-browser
          nix build -L .#neo4j-tree -o result-neo4j-tree
          nix build -L .#neo4j-image -o result-neo4j-image
        '';
      };
    });
  };
}
