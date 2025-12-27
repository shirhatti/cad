# 1U Rack Shelf Device Mounts

3D-printable retention brackets for securing devices to 1U 19" vented rack shelves using M4/M5 screws with heat-set threaded inserts.

![Vented Rack Shelf](https://m.media-amazon.com/images/I/71PxQFM0BPL._AC_SL1500_.jpg)

## Overview

This collection includes mounting solutions for various devices commonly installed in home lab rack setups. All designs use the same attachment method: threaded insert bosses that align with shelf ventilation slots, secured with M4/M5 screws from below. No drilling or permanent modifications required.

## Projects

### 1. Apple TV Retention Bracket (`apple_tv_retention_bracket.scad`)

A top-down retention bracket that clamps over the Apple TV 4K and secures to the shelf using M4/M5 screws with heat-set threaded inserts. Front and back are completely open for cable access and airflow.

**Features:**
- Two-sided retention walls (left/right only, 10mm thick)
- Front and back completely open for cable access
- Large center cutout (73mm × 93mm) for top ventilation
- Four threaded insert bosses at wall corners (12mm dia × 10mm tall)
- M4 or M5 screws insert from below shelf through vent slots
- Fully parametric via Customizer

**Device Specs (Apple TV 4K, 3rd Gen):**
- Dimensions: 93mm × 93mm × 31mm
- Weight: 208-214g
- 7mm clearance above device (38mm wall height)

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
- Print Time: ~2-3 hours

### 2. WiiM Amp Retention Bracket (`wiim_amp_retention_bracket.scad`)

A top-down retention bracket that clamps over the WiiM Amp and secures to the shelf using M4/M5 screws with heat-set threaded inserts. Front and back are completely open for port and cable access.

**Features:**
- Two-sided retention walls (left/right only, 10mm thick)
- Front and back completely open for port access
- Large center cutout (170mm × 190mm) for top ventilation
- Four threaded insert bosses at wall corners (12mm dia × 10mm tall)
- M4 or M5 screws insert from below shelf through vent slots
- Fully parametric via Customizer

**Device Specs (WiiM Amp):**
- Dimensions: 190mm × 190mm × 63mm
- 7mm clearance above device (70mm wall height)

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

1. Print the desired bracket (upside-down orientation)
2. Install heat-set threaded inserts into the four boss locations
3. Position bracket on shelf, aligning bosses over ventilation slots
4. Insert M4/M5 screws from below the shelf through vent slots
5. Tighten screws to secure bracket to shelf
6. Place device inside bracket

## Design Philosophy

All designs share common principles:
- **No permanent modifications** - Screws through existing vent slots
- **Secure attachment** - Threaded inserts provide strong, reusable threads
- **Ventilation-friendly** - Open designs for airflow
- **Print-optimized** - No supports, minimal overhangs
- **Parametric** - Customizable via OpenSCAD Customizer

## Files

- `apple_tv_retention_bracket.scad` - Apple TV 4K bracket
- `wiim_amp_retention_bracket.scad` - WiiM Amp bracket
