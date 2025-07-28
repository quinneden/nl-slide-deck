{
  description = "Slidev for Neuralink Presentation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.aarch64-darwin.default = pkgs.mkShell {
        name = "slide-deck";
        packages = with pkgs; [
          pnpm
          nodejs
        ];
      };
    };
}
