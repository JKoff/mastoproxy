{ pkgs ? import <nixpkgs> {} }:

pkgs.crystal.buildCrystalPackage {
  pname = "mastoproxy";
  version = "0.1.0";
  src = fetchFromGitHub {
    owner = "JKoff";
    repo = "mastoproxy";
    rev = "placeholder";
    hash = "placeholder";
  };
  crystal = pkgs.crystal;
  shardsFile = ./shards.nix;
  crystalBinaries.mastoproxy.src = "src/main.cr";
}
