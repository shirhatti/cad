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
            # OpenSCAD itself: brew install --cask openscad
            # (Nix version doesn't work on macOS - Qt/GUI issues)

            # Build tools
            just                 # Task runner (like make, but simpler)
            watchexec            # File watcher for auto-rebuild

            # Image tools (for preview generation)
            imagemagick          # Convert PNG renders to thumbnails

            # Python environment for SVG processing
            (python3.withPackages (ps: with ps; [
              # No external dependencies needed - using stdlib only
            ]))

            # MCP server support
            uv                   # Python package runner for openscad-mcp

            # 3D printing slicer
            # Orca Slicer: Install from https://github.com/OrcaSlicer/OrcaSlicer/releases
            # (Nix version not available on macOS)
          ];

          shellHook = ''
            echo "📐 OpenSCAD dev environment"

            # Check if OpenSCAD is installed via Homebrew
            if command -v brew >/dev/null 2>&1; then
              OPENSCAD_APP=$(brew info --cask openscad --json=v2 2>/dev/null | jq -r '.casks[0].artifacts[] | select(.app?) | .app[0]' 2>/dev/null || echo "")
              if [ -n "$OPENSCAD_APP" ] && [ -d "/Applications/$OPENSCAD_APP" ]; then
                OPENSCAD_BIN="/Applications/$OPENSCAD_APP/Contents/MacOS/OpenSCAD"
                export PATH="$(dirname "$OPENSCAD_BIN"):$PATH"
                echo "   OpenSCAD: $(basename "$OPENSCAD_APP" .app)"
              else
                echo "   ⚠️  OpenSCAD not found"
                echo "   Install with: brew install --cask openscad"
              fi
            else
              echo "   ⚠️  Homebrew not found"
            fi

            # Check if Orca Slicer is installed
            # Install from: https://github.com/OrcaSlicer/OrcaSlicer/releases
            if [ -d "/Applications/OrcaSlicer.app" ]; then
              ORCA_VERSION=$(/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer --version 2>&1 | head -1 || echo "OrcaSlicer")
              echo "   $ORCA_VERSION"
              export ORCA_SLICER_PATH="/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer"
            else
              echo "   ⚠️  Orca Slicer not found"
              echo "   Install from: https://github.com/OrcaSlicer/OrcaSlicer/releases"
            fi

            echo ""
            echo "Commands:"
            echo "   just gui FILE        - open in OpenSCAD GUI"
            echo "   just preview FILE    - generate PNG preview"
            echo "   just build           - render all to STL"
            echo "   just watch           - auto-rebuild on changes"
            echo ""
            echo "Print workflow:"
            echo "   just render FILE     - render .scad to STL"
            echo "   just slice FILE      - slice STL to 3MF"
            echo "   just open-slice FILE - open 3MF in Orca Slicer"
            echo "   just prepare FILE    - render + slice + open (complete workflow)"
            export VSCODE_PROFILE="openscad"
          '';
        };
      });
    };
}
