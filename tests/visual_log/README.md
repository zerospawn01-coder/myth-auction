# O6 Visual Log

- Runtime: Godot 4.7 stable on Windows
- Viewport: 480 × 854
- Flow: initial intake screen → wired intake button → wired visual-observation button
- `o6_480x854_initial.png`: initial `UNRECEIVED` state
- `o6_480x854_observed.png`: observation tab after `obs_visual` commits

Generate the images with:

```text
Godot_v4.7-stable_win64.exe --path . --script res://tests/m63_observe_full_acceptance_test.gd -- --write-visual-log
```

These images are Windows runtime acceptance artifacts. They do not constitute
Android/iOS hardware certification.
