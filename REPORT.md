# Primordial Dish — Technical Report

An interactive artificial-life petri dish for Godot 4.7: a GPU-accelerated
"Particle Life" simulation where a small attraction/repulsion matrix between
colored particle species produces emergent behavior — cells with membranes,
symbiotic colonies, polymer-like chains — and where the rule matrix itself is
the instrument you play.

## What it is

- 2400 particles, 2–8 species, on a toroidal (wrap-around) 2D world.
- Each ordered pair of species has a coefficient in a K×K matrix:
  positive = attract, negative = repel. Everything — cells, hunters,
  chains, colonies — falls out of that one matrix plus friction, a hard
  short-range repulsion zone, and an interaction radius.
- Live controls: pause, 1–5x time, all physical parameters, every matrix
  entry, randomize/mutate/zero, presets, and a mouse "hand of god"
  (LMB attract / RMB repel).
- Ships with 5 hand-selected regimes (presets `1`–`5`), each captured from
  the running simulation and reproducible from its stored seed + matrix.

## Why this and not something else

Chosen for the ratio: a few hundred lines of rules paying out behavior that
looks alive, and an evolvable rule set that makes *selecting for surprise* the
core interaction. Alternatives considered and set aside (full reasoning in
JOURNAL.md): Physarum (beauty over behavior), Lenia (math risk), WFC/terrain
(static output), evolving creatures (scope), generative music (can't hear my
own output). Godot over Unity because this session's tooling has full
godot-mcp instrumentation (run/screenshot/FPS/input-injection) and no Unity
equivalent — a simulation build lives on its observation loop.

## Architecture

Four GDScript files + one scene + data, all in `godot/`:

| file | role |
|---|---|
| `gpu_sim.gd` | Simulation core. RenderingDevice compute shader (GLSL, compiled at runtime) does brute-force N² force accumulation + integration + toroidal wrap, ping-ponging between buffer pairs each step. CPU keeps authoritative mirrors of species/matrix (uploaded on change) and reads positions back once per frame for rendering. |
| `sim.gd` | Reference CPU implementation with a uniform-grid neighbor search (O(n)-ish). Same public API; automatic fallback when no RenderingDevice exists. Ran at ~2 FPS at N=2400 — kept for correctness reference and non-Vulkan contexts. |
| `main.gd` | Wiring: sim selection (`GpuSim if is_supported()`), procedural soft-dot texture + MultiMeshInstance2D rendering (per-instance species colors, additive blend), hotkey actions, presets (scan/load/save/snapshot), full-res screenshot capture, mouse force forwarding. |
| `ui.gd` | Programmatic control panel: parameter sliders, species count, the K×K matrix editor (SpinBoxes colored by row/column species), preset UI, hints. |

Force law (normalized `r ∈ [0,1]` over `rmax`):
`r < β` → universal repulsion `r/β − 1`; otherwise a triangle peaking at
`r = (1+β)/2` with height `matrix[a][b]`. Integration: `v = v·damping + F·ff·dt`,
`p += v·dt`, then `mod()` wrap (GLSL `mod` ≡ `fposmod`).

Data flow per physics tick: sliders/push-constants → 1..5 compute dispatches
(substeps) → `buffer_get_data` readback (~19 KB) → MultiMesh transforms.
The GPU brute force was deliberate over a CPU spatial grid: at N=2400
(5.76 M pair evaluations/step) it's sub-millisecond on an RX 6650 XT and
removes the grid code from the correctness surface entirely.

Key decisions:
- **Ping-pong SSBOs** instead of barriers: each step reads set A and writes
  set B; no in-dispatch races, no `compute_list_add_barrier` reasoning.
- **Deterministic RNG stream** (seeded `RandomNumberGenerator` on CPU):
  every matrix ever shown is reproducible by replaying inputs — which
  literally recovered a lost preset (see JOURNAL.md entry 3).
- **Hotkeys as Godot input actions** (`pl_*` in `project.godot`): playable
  by keyboard *and* remotely injectable via godot-mcp — that's how the
  preset hunt and evidence screenshots were driven.
- **Presets are plain JSON** in `res://presets/` (shipped) and
  `user://presets/` (saved in-app): seed, K, N, rmax, β, damping, force
  factor, full matrix.

## Current state (actually executed)

Run inside Godot 4.7 via godot-mcp on an RX 6650 XT, window 1152×648:

- **260 FPS** at 2400 particles, 1x speed (frame 4.2 ms, physics 2.6 ms);
  ~58–60 FPS at 3x; 167 FPS measured in an earlier denser regime. The GDScript
  CPU fallback: ~2 FPS — the GPU move was an ~80–130x speedup.
- All 5 presets loaded via hotkeys and screenshot-verified live; evidence in
  `godot/screenshots/0{1..5}_*.png` captured from the running game (press `P`).
- Controls verified live: presets (1–5), randomize (R), time speed ([ ]),
  snapshot (G), screenshot (P), startup auto-load of `genesis`.
- The force-impulse chain (apply_radial → push constants → shader branch →
  integration) is executed-verified: hold `C` ("stir") applies the same
  call at world center; a 7.5 s hold visibly congregated the entire field
  at 260 FPS. Only the one-line `get_global_mouse_position()` wiring of
  LMB/RMB and individual matrix SpinBox edits remain review-level (the
  SpinBox path was fixed during review — missing GPU re-upload — and
  shares the verified randomize/mutate upload call). Wiggle both by hand.
- Clean project run (`godot --path godot --quit-after 3`): zero script
  errors, zero RID leaks on shutdown.

## How to run

Open `godot/` in Godot 4.7 and press F5 (main scene is set). Controls:
`Space` pause · `R` randomize · `M` mutate · `1–5` presets · `[` `]` time
speed · `G` snapshot current rules as a new preset · `P` save a screenshot ·
`C` (hold) stir everything toward the center · LMB pull / RMB push particles. Everything is also in the right-hand panel.

## Provenance

All code written this session, from scratch. The force law is the classic
"Particle Life / Clusters" family of rules (Jeffrey Ventrella's clusters;
popularized by Tom Mohr's and Hunar Ahmad's web demos) — a concept, not
copied code. No external assets, libraries, or datasets. Godot 4.7 itself:
MIT.

## What I'd change / where it goes next

- **Verification gap**: wire one integration test that drives the game
  headless (input actions work headless) and asserts structures form
  (e.g., clustering coefficient rises) — currently everything was verified
  by eyeballing screenshots.
- **Headroom is free**: 260 FPS at N=2400 means N=6000–10000 is reachable;
  beyond ~10k the N² shader wants the grid back (tile/shared-memory
  neighbor search in compute).
- **Evolution gallery** (the original stretch): keep a population of
  matrices, mutate, let the observer keep favorites across generations.
  Journal entry 3 records why I'm now ambivalent — manual selection turned
  out to be the most engaging part.
- **Species-dependent radii / asymmetric β**, and per-species counts
  instead of uniform slices — known knobs for richer ecology.
- Readback could go double-buffered async (`buffer_get_data_async`) to
  remove the last sync stall.
