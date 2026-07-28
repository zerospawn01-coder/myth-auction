# Aether Fountain: Research System Design

This document turns the research loop into an implementation contract for Godot.

## 1. Core Loop

Research should not be a passive point-farming system.

The intended flow is:

```text
research question
-> search for sources
-> collect evidence
-> design or delegate experiments
-> observe and record results
-> synthesize claims from multiple sources
-> pass safety review
-> apply to technology or world settings
```

The player role is not to write essays. The player decides:

- which sources count as evidence
- what to doubt
- which experiment can actually verify the claim
- whether the result is safe enough to apply

## 2. ResearchCase Model

Each research case should separate the following data types:

```text
ResearchCase
├─ Question
├─ Hypothesis
├─ EvidenceRecord
├─ ExperimentOrder
├─ ObservationRecord
├─ Claim
└─ ResearchResult
```

This separation keeps the system auditable and prevents one blob of text from acting as both source material and conclusion.

## 3. Search Returns Sources, Not Answers

Search should collect candidate documents, not solve the question.

The player enters short constraints such as:

```text
target: B-07
phenomenon: tissue collapse
material: ether fluid
period: last 30 days
source type: experiment record
```

Search results should be document cards with metadata:

- source name
- category
- relevance
- reliability
- author
- age
- condition

Search results may include:

- correct data
- outdated reports
- mistaken speculation
- politically altered records

The internal model must distinguish:

```text
what a source says
!=
what is objectively true in the world
```

## 4. Evidence Cards

Copying should preserve provenance.

The player can copy a passage into the research notebook as an evidence card, not as raw text alone.

Example:

```text
quote:
"At concentrations above 42%, membrane collapse accelerated sharply."

source:
Cultivation Tank Incident Report 17-B

author:
Maintenance Team 2

document_id:
DOC-17B-042

location:
section 4, paragraph 3
```

Evidence should be classifiable as:

- supports hypothesis
- contradicts hypothesis
- background information
- unverified information
- conflicting information

## 5. Document Quality Model

Use multiple indicators instead of a single trust score.

Recommended fields:

- relevance
- reliability
- completeness
- freshness
- reproducibility
- provenance

These values should be independent. A document can be highly relevant but incomplete, or reliable but outdated.

## 6. Experiment Design

Experiments should be designed more than manually played.

The player chooses:

- hypothesis to test
- sample to use
- control group
- variable to change
- fixed conditions
- equipment
- safety threshold
- abort condition
- required measurements

Example:

```text
hypothesis:
high-concentration ether fluid causes tissue collapse

test group:
42% concentration

control group:
20% concentration

fixed conditions:
temperature, culture time, subject, voltage

measurements:
membrane damage rate, metabolism, mutation index

abort condition:
mutation index above 70
```

This keeps research strategic instead of turning it into repetitive execution.

## 7. Delegation

Delegation should not be a "skip research" button.

The player should still decide:

- research objective
- experiment conditions
- budget cap
- safety standards
- submission format
- acceptance threshold

The delegate performs:

- experiment operations
- measurement
- document sorting
- first-pass analysis

Suggested delegate archetypes:

- public institute: reliable, slow, restricted
- private lab: fast, expensive
- military division: precise, ownership-heavy
- freelance technician: cheap, irregular
- AI analysis unit: high throughput, may discard anomalies

Delegation should carry risk:

- sample consumption
- information leakage
- measurement bias
- political alteration
- missing report sections
- ownership claims
- ethics violations

## 8. Auditability

Delegate output must be inspectable.

The result should include:

- experiment report
- measurement data
- used equipment
- responsible staff
- sample ID
- execution time
- conditions
- anomalies
- missing values
- report hash

The player can accept the report, request re-experimentation, or request audit.

## 9. Observation Records

Observation records should be structured, not pure free text.

Recommended fields:

- observer
- target
- timestamp
- equipment
- environment condition
- observation precision
- raw data
- short memo

Observed values can be selected from structured options such as:

- appearance
- activity level
- color tone
- abnormal motion
- risk sign
- related equipment

This is especially important for mobile input.

## 10. Observation Resolution

Different instruments should reveal different layers of truth.

Examples:

- naked eye: color, shape, motion, damage
- simple microscope: cell structure, parasites, tissue change
- Trait Analyzer: genetic traits, mutation tendency, compatibility
- advanced scanner: internal energy distribution, latent defects
- long-term observation: lifespan, environmental adaptation

This should connect directly to observed-world fixation.

An object should not reveal all truth at once. Each observation method fixes a different layer.

## 11. Claim and Result

Research results should be claims with confidence, not simple pass/fail outputs.

Recommended shape:

```text
claim:
B-07 tissue collapse is likely caused by the combined effect of high-concentration ether fluid and control-chip interference

confidence:
82%

supporting evidence:
4

contradictions:
1

open issues:
chip manufacturing lot differences

reproduction:
2 of 2 successful
```

Suggested thresholds:

- below 40%: archive as memo only
- 40-69%: provisional actions allowed
- 70-89%: limited deployment allowed
- 90%+: standard technology registration allowed

The research conclusion and the permission to apply that conclusion should remain separate.

## 12. Safety Review

Research may support a claim without making it safe.

Safety review should decide whether the result can affect:

- technology
- lore
- facility rules
- gameplay systems

This keeps research aligned with the project's audit and gate philosophy.

## 13. Resource Model

Research should consume more than just points.

Recommended constraints:

- time
- money
- samples
- equipment occupancy
- researcher availability
- information secrecy
- facility safety
- research reputation

Expensive or destructive experiments should force meaningful tradeoffs.

## 14. Player, Delegation, and Automation

Split research work into three bands:

### Player decides directly

- research question
- hypothesis selection
- source evaluation
- experiment design
- contradiction handling
- final conclusion
- safety approval

### Delegate can do

- source search
- routine experiments
- measurement
- sample processing
- long-term observation
- data cleanup

### Automation can do

- duplicate removal
- unit conversion
- charting
- anomaly detection
- ID assignment
- historical cross-checks

## 15. UI Structure

For a vertical layout, split research into four pages:

```text
1. Question
2. Search
3. Experiment
4. Notebook
```

The notebook should behave like a persistent clipboard where evidence can be stored, categorized, and attached to a hypothesis.

## 16. MVP Scope

The minimum useful implementation should include:

- one research case
- three hypotheses
- six to ten source documents
- evidence copy feature
- three observation record types
- two experiment templates
- one delegate location
- three result tiers
- one safety review screen

Suggested starting question:

```text
Why do early culture subjects collapse in a short time?
```

## Runtime Files

- `res://scripts/research/research_state.gd`
- `res://scripts/research/hypothesis_board.gd`
- `res://scripts/core/subject_workspace.gd`
- `res://scripts/knowledge/knowledge_state.gd`
- `res://scripts/publication/publication_state.gd`
- `res://scripts/auction/auction_state.gd`

