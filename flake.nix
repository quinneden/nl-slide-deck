{
  description = "Slidev for Neuralink Presentation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, self }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = f: lib.genAttrs systems (system: f { pkgs = import nixpkgs { inherit system; }; });
    in
    {
      packages = forEachSystem (
        { pkgs }:
        {
          default = self.packages.${pkgs.system}.slide-deck;
          slide-deck = pkgs.callPackage ./package.nix { };
        }
      );

      devShells = forEachSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            name = "slide-deck";
            packages = with pkgs; [
              pnpm
              nodejs
            ];
          };
        }
      );
    };
}
