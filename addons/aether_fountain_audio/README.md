# Aether Fountain Audio

Procedural Godot 4 audio asset derived from `aether-fountain.zip`.

The source ZIP contains a WebAudio `AudioEngine.ts` with CRIWARE ADX-style event cues. This asset ports that design to Godot with an `AudioStreamGenerator` synthesizer. Placeholder WAVs are also placed under `res://assets/audio/placeholders/` for future CRI Atom Craft authoring.

## Files

- `aether_audio_engine.gd` - runtime audio engine node.
- `aether_audio_debug_panel.gd` - optional UI panel for auditioning cues and AISAC-like parameters.
- `plugin.cfg` / `plugin.gd` - editor add-on metadata.
- `res://scripts/audio_bus.gd` - autoload facade used by gameplay scripts.
- `res://data/audio_cues.json` - cue manifest and future CRIWARE handoff data.

## Runtime API

Preferred gameplay API:

```gdscript
AudioBus.set_parameters(60.0, 35.0)
AudioBus.play_cue("cue_gene_mixer_complete")
AudioBus.play_cue("cue_lab_ambience_loop")
AudioBus.stop_cue("cue_lab_ambience_loop")
```

Direct engine API:

```gdscript
const AetherAudioEngine = preload("res://addons/aether_fountain_audio/aether_audio_engine.gd")

var audio := AetherAudioEngine.new()
add_child(audio)
audio.initialize()
audio.set_master_volume(0.5)
audio.set_parameters(60.0, 35.0)
audio.play_cue("cue_gene_mixer_complete")
```

Looping cues stay active until stopped:

```gdscript
audio.play_cue("cue_lab_ambience_loop")
audio.play_cue("cue_gene_mixer_loop")
audio.stop_mixer_loop()
audio.play_cue("cue_gate_scan")
audio.stop_scan_loop()
```

## Cue Categories

- `UI`
- `Device`
- `Gate`
- `Bioroid`
- `Mission`
- `Ambience`

Each category has a volume bus inside the engine:

```gdscript
audio.set_category_volume("Gate", 0.8)
```

## Dynamic Parameters

`set_parameters(risk, corruption)` acts like the source app's AISAC controls:

- `risk` changes the gate scanner sweep rate and pitch.
- `corruption` destabilizes the lab ambience drone.
- high-priority cues duck the ambience temporarily, matching the source REACT-style behavior.
