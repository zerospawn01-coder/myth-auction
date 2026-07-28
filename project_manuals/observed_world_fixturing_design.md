# Aether Fountain: Observed World Fixation Design

This document turns the "observed world fixation" concept into an implementation contract for Godot.

## 1. Core Principle

The world does not need to be fully generated up front.

Instead, each entity exists in a latent state until the player observes it. Observation commits the entity into canonical state, and that state must remain stable for the rest of the run.

This design is especially suitable for:

- books and documents
- containers and drawers
- specimen metadata
- NPC personal records
- unvisited rooms and buildings
- radio broadcasts
- market inventories
- minor flavor lore

It should be used carefully for:

- main story culprits
- already visible physical structures
- player history
- major faction motives
- victory-critical rules

## 2. State Model

Each latent object should move through a small, explicit state machine.

```text
UNOBSERVED
  Only classification, location, and constraints exist.

SELECTED
  The player has picked up or focused the object, but content is still latent.

OBSERVED
  Observation triggered generation.

COMMITTED
  The generated record has been stored and becomes canonical.
```

The `OBSERVED` and `COMMITTED` transitions can be performed in the same action when the observation result is valid.

If validation fails, return a safe fixed fallback such as:

```text
文字が激しく損傷しており判読できない
```

## 3. Deterministic Generation Contract

Observation must not be random at the moment of opening.

The content should be derived from stable inputs:

- world seed
- shelf or container ID
- slot position
- region
- era
- player progression
- allowed content table
- generation schema version

Example latent book record:

```text
latent_object_id: SHELF-02-SLOT-031
content_status: UNOBSERVED
```

Example committed book record:

```text
book_id: BK-82F4A91
origin_shelf_id: SHELF-02
title: 人工配列の安定化に関する基礎研究
author: Dr. Emil Rosen
published_year: 2084
security_level: 2
content_seed: 834921
content_status: COMMITTED
```

The content seed should be derived from stable world inputs so the same object always resolves to the same result.

## 4. Shelf and Container Profiles

Classification must constrain what can be generated.

Shelf profiles should define:

- domain weights
- publication period
- confidentiality
- physical condition
- allowed rarity bands

Example:

```text
shelf_profile:
  domain:
    genetics: 0.55
    virology: 0.25
    laboratory_management: 0.15
    personal_notes: 0.05

  publication_period:
    min_year: 2040
    max_year: 2090

  confidentiality:
    public: 0.60
    internal: 0.30
    classified: 0.10

  physical_condition:
    clean: 0.10
    worn: 0.55
    damaged: 0.35
```

This is not cosmetic metadata. It is a generation boundary.

## 5. Canon and Derived Facts

To avoid contradictions, the system should separate the type of truth being stored.

```text
CANON_FACT
  Immutable world setting.

DERIVED_FACT
  Fact inferred from CANON_FACT.

LOCAL_RUMOR
  Can be wrong, biased, or incomplete.

PERSONAL_OPINION
  Subjective statement.

UNKNOWN
  Not yet fixed.
```

This allows documents to disagree without breaking the world model, as long as the internal canonical layer remains consistent.

## 6. Save Data Rules

Do not persist every latent entity.

Persist only what has been observed or otherwise fixed in canon.

Recommended fields:

```text
book_id
origin_id
generation_seed
template_id
important_variables
content_hash
observation_tick
```

If the final text is generated through non-deterministic systems, store the final committed content as well. Seed-based reconstruction alone is not reliable in that case.

## 7. Anti-Reroll Rule

Opening and closing the UI must not reroll results.

The object should resolve from its stable seed and schema, not from the current frame's random state.

This prevents save-scumming and preserves the sense that the world was already there waiting to be observed.

## 8. Guaranteed Progress

Important story information should never remain unreachable.

Use guaranteed slots or bounded guarantees such as:

- one clue within every 10 reads
- fixed document on the third item in a specific shelf
- special results unlocked only after related NPC conversations

The appearance should remain incidental, but the system should be authored to prevent dead ends.

## 9. Recommended MVP Targets

The first implementation should focus on three object classes:

1. research facility bookshelves
2. unparsed biological specimens
3. researcher personal records

These are enough to establish the loop where exploration steadily fixes the history of the facility.

## 10. Practical Implementation Notes

The project already uses deterministic, ledger-backed state transitions for research, publication, and knowledge promotion. This design should follow the same philosophy:

- do not create mutable truth on every open
- validate provenance before committing
- store canonical record IDs separately from display text
- keep latent classification separate from fixed content

If this system is expanded later, treat rooms, radios, markets, and NPC histories as the same pattern: latent classification first, canonical content on observation.

## Runtime Files

- `res://scripts/knowledge/knowledge_state.gd`
- `res://scripts/knowledge/known_fact_record.gd`
- `res://scripts/core/subject_workspace.gd`
- `res://scripts/research/research_state.gd`
- `res://scripts/publication/publication_state.gd`

