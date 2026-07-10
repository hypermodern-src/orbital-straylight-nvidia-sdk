{
  description = "NVIDIA SDK — CUDA 13.1 + Blackwell SM120 + NGC 25.12";

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      perSystem = { system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;

          overlays = [ ];

          config = {
            cudaSupport = true; # the monopoly
            rocmSupport = false; # the controlled opposition
            allowUnfree = true; # the price of admission
          };
        };
      };

      imports = [ ./nix/modules ];
    };

  inputs = {
    nixpkgs.url = "github:sensenet-ai/nixpkgs";
    systems.url = "github:nix-systems/default";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    # LLVM pinned to known-good SM120 support
    llvm-project = {
      url = "github:llvm/llvm-project/bb1f220d534b0f6d80bea36662f5188ff11c2e54";
      flake = false;
    };

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
}
