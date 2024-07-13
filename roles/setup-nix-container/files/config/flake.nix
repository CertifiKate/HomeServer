{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    inputs.sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, ... }:
    let 
      system = "x86_64-linux";
    in {

      nixosConfigurations."l-auth-01" = nixpkgs.lib.nixosSystem {
        modules = [ 
          ./base.nix 
          ./hosts/auth-01.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
}
