{ pkgs ? import <nixpkgs> {} }:

pkgs.crystal.buildCrystalPackage {
  pname = "mastoproxy";
  version = "0.1.0";
  src = fetchFromGitHub {
    owner = "JKoff";
    repo = "mastoproxy";
    rev = "c039ed5";
    hash = "c039ed5d17ec32997406912615bfd1579a61ef6b";
  };
  crystal = pkgs.crystal;
  shardsFile = ./shards.nix;
  crystalBinaries.mastoproxy.src = "src/main.cr";
}
