// Hex Cube - Open cube with hexagonal grid on all five faces
// Test project demonstrating the shared hex_grid library

use <../../lib/hex_grid.scad>

$fn = 32;

// ===== PARAMETERS =====
CUBE_SIZE = 60;          // Outer dimensions of the cube
WALL_THICKNESS = 2.5;    // Wall thickness
HOLE_DIA = 6;            // Diameter of hex grid holes
HOLE_SPACING = 10;       // Center-to-center spacing

// Margin from edges (no holes in this zone)
GRID_MARGIN = HOLE_SPACING;

// Inner dimensions
INNER_SIZE = CUBE_SIZE - 2 * WALL_THICKNESS;

// ===== MAIN MODULE =====

module hex_cube() {
    difference() {
        // Solid cube shell
        cube_shell();

        // Cut hex patterns into each face
        hex_cutouts();
    }
}

// Hollow cube (open on top)
module cube_shell() {
    difference() {
        // Outer cube
        cube([CUBE_SIZE, CUBE_SIZE, CUBE_SIZE]);

        // Inner cavity (open top)
        translate([WALL_THICKNESS, WALL_THICKNESS, WALL_THICKNESS])
        cube([INNER_SIZE, INNER_SIZE, CUBE_SIZE]);
    }
}

// Hex grid cutouts for all five faces
module hex_cutouts() {
    grid_size = CUBE_SIZE - 2 * GRID_MARGIN;

    // Bottom face (Z = 0, looking up)
    translate([CUBE_SIZE/2, CUBE_SIZE/2, -0.1])
    hex_grid_3d(
        width = grid_size,
        depth = grid_size,
        height = WALL_THICKNESS + 0.2,
        hole_dia = HOLE_DIA,
        spacing = HOLE_SPACING,
        center = true
    );

    // Front face (Y = 0, looking back)
    translate([CUBE_SIZE/2, -0.1, CUBE_SIZE/2])
    rotate([-90, 0, 0])
    hex_grid_3d(
        width = grid_size,
        depth = grid_size,
        height = WALL_THICKNESS + 0.2,
        hole_dia = HOLE_DIA,
        spacing = HOLE_SPACING,
        center = true
    );

    // Back face (Y = CUBE_SIZE, looking forward)
    translate([CUBE_SIZE/2, CUBE_SIZE + 0.1, CUBE_SIZE/2])
    rotate([90, 0, 0])
    hex_grid_3d(
        width = grid_size,
        depth = grid_size,
        height = WALL_THICKNESS + 0.2,
        hole_dia = HOLE_DIA,
        spacing = HOLE_SPACING,
        center = true
    );

    // Left face (X = 0, looking right)
    translate([-0.1, CUBE_SIZE/2, CUBE_SIZE/2])
    rotate([0, 90, 0])
    hex_grid_3d(
        width = grid_size,
        depth = grid_size,
        height = WALL_THICKNESS + 0.2,
        hole_dia = HOLE_DIA,
        spacing = HOLE_SPACING,
        center = true
    );

    // Right face (X = CUBE_SIZE, looking left)
    translate([CUBE_SIZE + 0.1, CUBE_SIZE/2, CUBE_SIZE/2])
    rotate([0, -90, 0])
    hex_grid_3d(
        width = grid_size,
        depth = grid_size,
        height = WALL_THICKNESS + 0.2,
        hole_dia = HOLE_DIA,
        spacing = HOLE_SPACING,
        center = true
    );
}

// Render the hex cube
hex_cube();
