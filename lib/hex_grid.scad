// Hexagonal Grid Utilities
// Shared library for creating hexagonal patterns
//
// Hexagonal grids provide:
// - Better structural strength than rectangular grids
// - More uniform material distribution
// - Improved airflow for ventilation applications
// - Aesthetically pleasing appearance

// Module: hex_grid_2d
// Creates a 2D hexagonal grid of circles (for use with linear_extrude)
//
// Parameters:
//   width    - Total width of the grid area
//   depth    - Total depth of the grid area
//   hole_dia - Diameter of each hole
//   spacing  - Center-to-center spacing between holes
//   center   - If true, center the grid at origin (default: true)
module hex_grid_2d(width, depth, hole_dia, spacing, center=true) {
    // Hexagonal grid geometry:
    // - Rows are offset by spacing/2 alternately
    // - Vertical spacing is spacing * sin(60°) = spacing * 0.866
    row_spacing = spacing * 0.866;

    rows = floor(depth / row_spacing);
    cols = floor(width / spacing);

    // Calculate centering offsets
    grid_width = (cols - 1) * spacing + spacing/2;  // Account for offset rows
    grid_depth = (rows - 1) * row_spacing;

    offset_x = center ? -grid_width / 2 : 0;
    offset_y = center ? -grid_depth / 2 : 0;

    translate([offset_x, offset_y, 0])
    for (row = [0 : rows - 1]) {
        row_offset = (row % 2) * spacing / 2;
        for (col = [0 : cols - 1]) {
            translate([col * spacing + row_offset, row * row_spacing, 0])
            circle(d=hole_dia);
        }
    }
}

// Module: hex_grid_3d
// Creates a 3D hexagonal grid of cylinders (cutouts for ventilation)
//
// Parameters:
//   width    - Total width of the grid area
//   depth    - Total depth of the grid area
//   height   - Height/thickness of the cylinders
//   hole_dia - Diameter of each hole
//   spacing  - Center-to-center spacing between holes
//   center   - If true, center the grid at origin (default: true)
module hex_grid_3d(width, depth, height, hole_dia, spacing, center=true) {
    linear_extrude(height=height)
    hex_grid_2d(width, depth, hole_dia, spacing, center);
}

// Module: hex_grid_panel
// Creates a solid panel with hexagonal hole pattern cut out
//
// Parameters:
//   width     - Panel width
//   depth     - Panel depth
//   thickness - Panel thickness
//   hole_dia  - Diameter of ventilation holes
//   spacing   - Center-to-center spacing between holes
//   margin    - Border margin without holes (default: spacing)
//   center    - If true, center panel at origin (default: true)
module hex_grid_panel(width, depth, thickness, hole_dia, spacing, margin=undef, center=true) {
    actual_margin = is_undef(margin) ? spacing : margin;

    offset_x = center ? 0 : width/2;
    offset_y = center ? 0 : depth/2;

    translate([offset_x, offset_y, 0])
    difference() {
        // Solid panel
        translate([0, 0, thickness/2])
        cube([width, depth, thickness], center=true);

        // Hex grid cutouts
        translate([0, 0, -0.1])
        hex_grid_3d(
            width = width - 2 * actual_margin,
            depth = depth - 2 * actual_margin,
            height = thickness + 0.2,
            hole_dia = hole_dia,
            spacing = spacing,
            center = true
        );
    }
}
