# 1U Rack Shelf Device Mounts

3D-printable retention systems for securing devices to 1U 19" vented rack shelves using snap-fit designs that clip into ventilation slots.

![Vented Rack Shelf](https://m.media-amazon.com/images/I/71PxQFM0BPL._AC_SL1500_.jpg)

## Overview

This collection includes mounting solutions for various devices commonly installed in home lab rack setups. All designs use the same attachment method: snap-fit clips that engage with standard rack shelf ventilation slots, requiring no drilling or permanent modifications.

## Projects

### 1. Apple TV Mount (`rack_shelf_apple_tv_mount.scad`)

A tray-style mount with integrated ventilation and cable management for Apple TV 4K.

**Features:**
- Snap-fit clips attach to ventilation slots (35.5mm × 5mm)
- Ventilation grid for passive cooling
- Cable management slot at rear
- Corner retaining clips keep Apple TV secure
- Optimized for 3D printing (minimal overhangs, 45° max angles)

**Device Specs (Apple TV 4K, 3rd Gen):**
- Dimensions: 93mm × 93mm × 31mm
- Weight: 208-214g

**Print Settings:**
- Material: PLA or PETG
- Layer Height: 0.20mm
- Infill: 20%
- Supports: None required
- Print Time: ~3-4 hours

### 2. Apple TV Retention Strap (`retention_strap.scad`)

A minimalist strap alternative that secures the Apple TV directly to the shelf without a tray.

**Features:**
- Ultra-lightweight design
- Allows Apple TV to sit directly on shelf
- Clips through ventilation slots
- Print on side for optimal strength
- No supports needed

**Print Settings:**
- Material: PLA or PETG
- Print Orientation: On its side
- Print Time: ~30-45 minutes

### 3. WiiM Amp Retention Bracket (`wiim_amp_retention_bracket.scad`)

A top-down retention bracket that clamps over the WiiM Amp and secures to the shelf using M4/M5 screws with heat-set threaded inserts. Front and back are completely open for port and cable access.

**Features:**
- Two-sided retention walls (left/right only, 10mm thick)
- Front and back completely open for port access
- Large center cutout (170mm × 190mm) for top ventilation
- Four threaded insert bosses at wall corners (12mm dia × 10mm tall)
- M4 or M5 screws insert from below shelf through vent slots
- Fully parametric via Customizer

**Device Specs (WiiM Amp):**
- Dimensions: 190mm × 190mm × 43mm
- 7mm clearance above device (50mm wall height)

**Hardware Required:**
- 4× M4 or M5 heat-set threaded inserts (6-8mm length)
- 4× M4 or M5 screws, 12-16mm length (socket head or pan head)

**Print Settings:**
- Material: PETG or ABS recommended (heat tolerance)
- Layer Height: 0.20mm
- Infill: 20-30%
- Perimeters: 3+ on insert bosses for strength
- Print Orientation: Upside-down (top plate on bed)
- Supports: None required
- Print Time: ~4-6 hours

## Shelf Compatibility

All designs are compatible with standard 1U vented rack shelves featuring:
- Slot dimensions: 20mm long × 6mm wide (approximately)
- Slot spacing: 35.5mm center-to-center
- Usable shelf area: 438mm × 252mm
- Material: SPCC steel, ~1mm thick

## General Assembly

1. Print the desired mount/bracket
2. Locate position on rack shelf ventilation slots
3. Align clips/tabs with slots
4. Press firmly to snap into place
5. Install device and route cables

## Design Philosophy

All designs share common principles:
- **No permanent modifications** - Snap-fit clips only
- **Tool-free installation** - Press-fit assembly
- **Ventilation-friendly** - Open designs for airflow
- **Print-optimized** - No supports, minimal overhangs
- **Parametric** - Customizable via OpenSCAD Customizer

## Files

- `rack_shelf_apple_tv_mount.scad` - Apple TV tray mount
- `retention_strap.scad` - Apple TV retention strap
- `wiim_amp_retention_bracket.scad` - WiiM Amp bracket
