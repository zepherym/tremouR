{
  description = "A nix flake for a Rust project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      cargoToml = fromTOML (builtins.readFile ./Cargo.toml);
      name =
        if cargoToml ? package && cargoToml.package ? name then
          cargoToml.package.name
        else
          baseNameOf (toString ./.);
      version = cargoToml.package.version or cargoToml.workspace.package.version or "0.0.0";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        overlays = {
          default = final: prev: {
            ${name} = inputs.self.packages.${prev.stdenv.hostPlatform.system}.default;
          };
          ${name} = inputs.self.overlays.default;
        };
      };

      perSystem =
        {
          pkgs,
          lib,
          inputs',
          ...
        }:
        let
          fenixPkgs = inputs'.fenix.packages;
          toolchainFile = ./rust-toolchain.toml;
          hasToolchain = builtins.pathExists toolchainFile;

          rustToolchain =
            if hasToolchain then
              fenixPkgs.fromToolchainFile {
                file = toolchainFile;
                sha256 = "sha256-OUIy1RMzJvwqM8cwkC+1hVHUF4B/TgGM1GGhqbooEXg=";
              }
            else
              fenixPkgs.combine [
                (fenixPkgs.complete.withComponents [
                  "cargo"
                  "clippy"
                  "rust-src"
                  "rustc"
                  "rustfmt"
                ])
                fenixPkgs.rust-analyzer-nightly
              ];

          craneLib = ((inputs.crane.mkLib pkgs).overrideToolchain rustToolchain).overrideScope (
            final: prev: {
              stdenvSelector = p: p.stdenvAdapters.useMoldLinker p.clangStdenv;
            }
          );
          src = craneLib.cleanCargoSource (craneLib.path ./.);

          waylandRuntimeLibs = with pkgs; [
            wayland
            libxkbcommon
            vulkan-loader
            libGL
            fontconfig
            freetype
            alsa-lib
          ];

          nativeBuildInputs = with pkgs; [
            pkg-config
            mold
            clang
            makeWrapper
          ];

          buildInputs = waylandRuntimeLibs;

          commonArgs = {
            pname = name;
            inherit version;
            inherit src nativeBuildInputs buildInputs;
            strictDeps = true;
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          pkg = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              meta.mainProgram = name;

              postInstall = ''
                wrapProgram $out/bin/${name} \
                  --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath waylandRuntimeLibs}"
              '';
            }
          );

          checks = {
            "${name}" = pkg;

            "${name}-clippy" = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            "${name}-fmt" = craneLib.cargoFmt {
              inherit src;
            };

            "${name}-test" = craneLib.cargoTest (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );
          };

        in
        {
          inherit checks;

          packages = {
            default = pkg;
            ${name} = pkg;
          };

          apps.default = {
            type = "app";
            program = lib.getExe pkg;
          };

          devShells.default = craneLib.devShell {
            inputsFrom = [ pkg ];
            LD_LIBRARY_PATH = lib.makeLibraryPath waylandRuntimeLibs;
          };
        };
    };
}
