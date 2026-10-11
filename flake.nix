{
  description = "dankSyncthing: Syncthing sync state for DankMaterialShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The plugin directory itself (the one containing plugin.json), which is
      # what DMS's `plugins.<name>.src` expects.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "dankSyncthing-plugin" { } ''
          cp -r ${./dankSyncthing} $out
          chmod +x $out/scripts/st-poll.sh
        '';
      });

      # Logic fixtures under node; `nix flake check` runs them.
      checks = forAll (pkgs: {
        tests = pkgs.runCommand "dankSyncthing-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
          cp -r ${./dankSyncthing} dankSyncthing
          cp -r ${./tests} tests
          node tests/run.mjs
          touch $out
        '';
      });

      # Registers the plugin with the DMS module the way dms-plugin-registry
      # does: `src` is filled in and `enable` defaults to false, so a user only
      # writes `programs.dank-material-shell.plugins.dankSyncthing.enable = true`.
      homeManagerModules.default = self.homeManagerModules.dankSyncthing;
      homeManagerModules.dankSyncthing =
        {
          config,
          lib,
          pkgs,
          options,
          ...
        }:
        let
          plugin = {
            enable = lib.mkDefault false;
            src = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          };

          # The stable flake, the unstable flake and nixpkgs each name the
          # module differently; register under whichever one is imported.
          names = builtins.filter (n: options ? programs.${n}.plugins) [
            "dankMaterialShell"
            "dank-material-shell"
            "dms-shell"
          ];

          enabled = lib.any (n: config.programs.${n}.plugins.dankSyncthing.enable) names;
        in
        {
          config = lib.mkMerge (
            map (n: { programs.${n}.plugins.dankSyncthing = plugin; }) names
            ++ [
              # scripts/st-poll.sh needs both on PATH.
              {
                home.packages = lib.mkIf enabled [
                  pkgs.curl
                  pkgs.jq
                ];
              }
            ]
          );
        };
    };
}
