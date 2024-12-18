{
  description = "Crystal development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Used by crystal server.
            crystal
            shards
            pkg-config
            openssl
            libxml2
            zlib
            libyaml
            pcre
            sqlite

            # Used by next.js server.
            nodejs_22
          ];

          shellHook = ''
            echo "Crystal development environment loaded"
            crystal --version
          '';
        };
      }
    );
}
