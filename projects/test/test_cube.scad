// Simple test cube for slicer comparison
// Compatible with MakerBot Customizer: https://customizer.makerbot.com/docs

// preview[view:south east, tilt:top diagonal]

/* [Dimensions] */
// Size of the cube in X direction
size_x = 10; // [5:1:50]

// Size of the cube in Y direction
size_y = 10; // [5:1:50]

// Size of the cube in Z direction
size_z = 10; // [5:1:50]

/* [Position] */
// Center the cube on the build plate
centered = false; // [true, false]

// Render the cube
cube([size_x, size_y, size_z], center=centered);
