# Myth Audio

Procedural Godot 4 audio asset derived from `myth-audio.zip`.

## Components

- `myth_audio_engine.gd` - runtime audio engine node.
- `myth_audio_debug_panel.gd` - optional UI panel for auditioning cues and AISAC-like parameters.

## Setup

1. Copy `addons/myth_audio` to your `addons` folder.
2. Ensure you have activated the plugin, though it is not strictly required if you instance the script manually.

## Usage

```gdscript
const MythAudioEngine = preload("res://addons/myth_audio/myth_audio_engine.gd")

var audio := MythAudioEngine.new()
```

## Runtime API

Preferred gameplay API:

```gdscript
AudioBus.set_parameters(60.0, 35.0)
AudioBus.play_cue("cue_bid_commit")
AudioBus.play_cue("cue_lab_ambience_loop")
AudioBus.stop_cue("cue_lab_ambience_loop")
```

Direct engine API:

```gdscript
const MythAudioEngineScript = preload("res://addons/myth_audio/myth_audio_engine.gd")

var audio := MythAudioEngineScript.new()
add_child(audio)
audio.initialize()
audio.set_master_volume(0.5)
audio.set_parameters(60.0, 35.0)
audio.play_cue("cue_bid_commit")
```

Looping cues stay active until stopped:

```gdscript
audio.play_cue("cue_lab_ambience_loop")
audio.play_cue("cue_gate_scan")
audio.stop_scan_loop()
```

## Cue Categories

- `UI`
- `Device`
- `Gate`
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
