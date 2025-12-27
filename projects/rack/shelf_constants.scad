// Shelf Constants - Shared between designs and tests
//
// This file defines the vented rack shelf slot pattern constants.
// Include this file in both design files and test files to ensure
// alignment calculations stay in sync.

// ============================================================
// Shelf Slot Pattern Constants
// ============================================================

// Slot dimensions
SLOT_LENGTH = 35.5;       // Slot length along Y-axis (mm)
SLOT_WIDTH = 5.5;         // Slot width along X-axis (mm)
SLOT_RADIUS = 2.75;       // Slot corner radius (mm)

// Slot pattern
SLOT_COLUMNS = 19;        // Number of slot columns
SLOT_ROWS = 3;            // Number of slot rows
SLOT_SPACING_X = 20;      // X-axis spacing between slot centers (mm)
SLOT_SPACING_Y = 53;      // Y-axis spacing between row centers (mm)

// Shelf dimensions
SHELF_WIDTH = 438;        // Usable shelf width (mm)
SHELF_DEPTH = 252;        // Usable shelf depth (mm)
SHELF_THICKNESS = 1.2;    // Shelf material thickness (mm)

// Derived values
SLOT_PATTERN_X_SPAN = (SLOT_COLUMNS - 1) * SLOT_SPACING_X;  // 360mm
SLOT_PATTERN_Y_SPAN = (SLOT_ROWS - 1) * SLOT_SPACING_Y;     // 106mm

// First slot position (pattern centered in shelf)
FIRST_SLOT_X = (SHELF_WIDTH - SLOT_PATTERN_X_SPAN) / 2;
FIRST_SLOT_Y = (SHELF_DEPTH - SLOT_PATTERN_Y_SPAN) / 2;
