# Rangoli Moulds

3D-printable Diwali rangoli moulds: floral mandalas in a traditional style. Each mould
is a network of thin walls tracing the rangoli's outlines. Lay it on the
floor, spoon a different colour of powder into each cell, then lift it
straight up to leave a crisp, multi-colour rangoli.

The moulds are about 450mm across, which is much bigger than the build plate.
Each one splits into a **centre** piece plus identical **wedges** that jigsaw
together. You print one wedge STL several times.

| Design | Pattern | Pieces | Per wedge | Whole mould |
| --- | --- | --- | --- | --- |
| `phool_mandala.scad` | 12 onion-dome petals with feather fans and finials over pointed petals; scallop, dot and confetti rings | 1 centre + 6 wedges | ~1h40m, 36 g | ~10h, ~220 g |
| `kamal_mandala.scad` | three layers of lotus petals (16-fold) around a ring of buds, a dot ring and a flower centre | 1 centre + 8 wedges | ~1h05m, 25 g | ~9h, ~215 g |
| `genda_mandala.scad` | marigold: round petals in two layers on a ruffled backing, ringed with leaves; a ring of five-petal blossoms and a flower centre (16-fold) | 1 centre + 8 wedges | ~1h00m, 23 g | ~8h30m, ~200 g |

Times and weights are for PLA with the repo's Bambu Lab A1 profile.

## Printing

Every design has a `part` Customizer option:

- `wedge` (default): print it 6 times for Phool, 8 times for Kamal and Genda
- `center`: print it once
- `assembly`: preview of the whole mould as printed
- `colours`: preview of a finished rangoli, with a suggested palette

Print as modelled, with the flat ties on the bed and the walls standing up.
No supports are needed (they're turned off for these models, because support
would fill the joint sockets). Wall thickness defaults to 1.2mm (three 0.4mm
lines) and wall height to 8mm.

`outer_diameter` scales the whole pattern from 300 to 480mm, and every size
still fits a 256×256mm plate. Wall and tie sizes stay the same at every scale.

## Using it

1. Flip every piece so the walls point down and the ties are on top.
2. Snap the wedges into the centre and into each other. The flat jigsaw knobs
   sit in the tie layer.
3. Fill each cell with powder. A spoon works for the big cells; a paper cone
   or a squeeze bottle works for the small ones. The ties sit above the
   powder, so you can pour straight past them.
4. Lift the mould straight up.

## How it's built (`rangoli_lib.scad`)

- **Walls**: each design draws its outlines as thin 2D walls for the whole
  disc. The library clips them into pieces.
- **Ties**: a stencil-style design would fall apart, because every ring and
  dot is a separate island. Here, radial spokes, ring ties and per-design
  ties (e.g. through the feather fans) join every wall into one rigid piece.
  The mesh check (`bodies = 1`) confirms nothing is left floating.
- **Joints**: jigsaw knobs on each wedge's +edge fit sockets on the
  neighbour's −edge. A knob on each wedge's inner arc reaches over the centre
  wall into the centre piece. `clearance` (default 0.15mm per side) sets the
  fit.
- **Seams** run along petal axes chosen so no seam cuts through a big
  motif off-centre.

Each design has a `*_test.scad` that checks knob placement and plate fit from
Ø300 to Ø480.
