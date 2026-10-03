{
  description = "OpenSCAD development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      # VS Code profile hint for auto-detection
      vscodeProfile = "openscad";

      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # OpenSCAD tools
            openscad-lsp         # Language server for IDE support
            # OpenSCAD itself: brew install --cask openscad@snapshot
            # (snapshot builds have the fast Manifold backend CI uses)
            # (Nix version doesn't work on macOS - Qt/GUI issues)

            # Build tools
            just                 # Task runner (like make, but simpler)
            watchexec            # File watcher for auto-rebuild

            # Image tools (for preview generation)
            imagemagick          # Convert PNG renders to thumbnails

            # Python toolchain (uv manages Python version + packages)
            uv                   # Fast Python package manager

            # 3D printing slicer
            # Orca Slicer: Install from https://github.com/OrcaSlicer/OrcaSlicer/releases
            # (Nix version not available on macOS)
          ];

          shellHook = ''
            echo "📐 OpenSCAD dev environment"

            # Check if OpenSCAD is installed via Homebrew
            if command -v brew >/dev/null 2>&1; then
              OPENSCAD_APP=$(brew info --cask openscad@snapshot --json=v2 2>/dev/null | jq -r '.casks[0].artifacts[] | select(.app?) | .app[0]' 2>/dev/null || echo "")
              if [ -n "$OPENSCAD_APP" ] && [ -d "/Applications/$OPENSCAD_APP" ]; then
                OPENSCAD_BIN="/Applications/$OPENSCAD_APP/Contents/MacOS/OpenSCAD"
                export PATH="$(dirname "$OPENSCAD_BIN"):$PATH"
                echo "   OpenSCAD: $(basename "$OPENSCAD_APP" .app)"
              else
                echo "   ⚠️  OpenSCAD not found"
                echo "   Install with: brew install --cask openscad@snapshot"
              fi
            else
              echo "   ⚠️  Homebrew not found"
            fi

            # Check if Orca Slicer is installed
            # Install from: https://github.com/OrcaSlicer/OrcaSlicer/releases
            if [ -d "/Applications/OrcaSlicer.app" ]; then
              ORCA_VERSION=$(/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer --version 2>&1 | head -1 || echo "OrcaSlicer")
              echo "   $ORCA_VERSION"
            else
              echo "   ⚠️  Orca Slicer not found"
              echo "   Install from: https://github.com/OrcaSlicer/OrcaSlicer/releases"
            fi

            echo ""
            echo "Setup:"
            echo "   just setup           - install Python deps + pre-commit hooks"
            echo "   just toolchain       - install pinned OpenSCAD + OrcaSlicer (Linux)"
            echo ""
            echo "Linting:"
            echo "   just lint            - check Customizer compliance"
            echo "   just test / check    - unit tests / validate models render"
            echo "   just pre-commit      - run all pre-commit hooks"
            echo ""
            echo "OpenSCAD:"
            echo "   just build           - render all to STL"
            echo "   just gui FILE        - open in OpenSCAD GUI"
            echo "   just watch           - auto-rebuild on changes"
            echo ""
            echo "Print workflow:"
            echo "   just render FILE     - render a single file"
            echo "   just slice           - slice rendered STLs to 3MF"
            export VSCODE_PROFILE="openscad"
          '';
        };
      });
    };
}
