// Shelf Constants - Shared between designs and tests
//
// This file defines the vented rack shelf slot pattern constants.
// Include this file in both design files and test files to ensure
// alignment calculations stay in sync.

/* [Hidden] */

// ============================================================
// Shelf Slot Pattern Constants
// ============================================================

// Slot dimensions
SLOT_LENGTH = 35.5;
SLOT_WIDTH = 5.5;
SLOT_RADIUS = 2.75;

// Slot pattern
SLOT_COLUMNS = 19;
SLOT_ROWS = 3;
SLOT_SPACING_X = 20;
SLOT_SPACING_Y = 53;

// Shelf dimensions
SHELF_WIDTH = 438;
SHELF_DEPTH = 252;
SHELF_THICKNESS = 1.2;

// Derived values
SLOT_PATTERN_X_SPAN = (SLOT_COLUMNS - 1) * SLOT_SPACING_X;
SLOT_PATTERN_Y_SPAN = (SLOT_ROWS - 1) * SLOT_SPACING_Y;

// First slot position (pattern centered in shelf)
FIRST_SLOT_X = (SHELF_WIDTH - SLOT_PATTERN_X_SPAN) / 2;
FIRST_SLOT_Y = (SHELF_DEPTH - SLOT_PATTERN_Y_SPAN) / 2;
