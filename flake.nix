{
  description = "RealWorld example app in Haskell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        realworld-haskell = pkgs.haskellPackages.callCabal2nix "realworld-haskell" ./. { };

        default = self.packages.${pkgs.system}.realworld-haskell;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.haskellPackages.shellFor {
          packages = _: [ self.packages.${pkgs.system}.realworld-haskell ];

          nativeBuildInputs = [
            pkgs.cabal-install
            pkgs.haskellPackages.haskell-language-server
            pkgs.haskellPackages.ormolu
            pkgs.nixpkgs-fmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
