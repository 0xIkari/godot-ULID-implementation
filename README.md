# Godot ULID Implementation

A spec-compliant [ULID](https://github.com/ulid/spec) implementation in pure GDScript for Godot 4, with an optional entity registry for tracking and searching ULIDs by name and type.

Godot doesn't ship a built-in UUID or ULID generator. This library fills that gap with a single-file, zero-dependency implementation you can drop into any project.

## Features

**Core (ulid.gd)**
- Full [ULID specification](https://github.com/ulid/spec) compliance: Crockford's Base32, 48-bit millisecond timestamps, 80-bit cryptographic randomness
- Monotonic ordering within the same millisecond
- Clock skew tolerance
- No 64-bit overflow: uses a byte-array approach for the 80-bit random component, sidestepping GDScript's signed integer limit entirely
- Lexicographic sorting gives you chronological ordering with default string comparison
- Single file, zero dependencies

**Registry (ulid_registry.gd) — optional**
- Track ULIDs with human-readable names and type tags
- Indexed lookup by type and name without full-registry scans
- Partial name search for debug consoles and player-facing search
- Serialize/deserialize for save file integration
- Auto-detected by the ULID core when both are loaded — no configuration needed

## Quick Start

### Core Only

1. Copy `ulid.gd` into your project (e.g., `res://addons/gdulid/ulid.gd`)
2. Register it as an Autoload named `ULID` in **Project > Project Settings > Globals**
3. Generate ULIDs from anywhere:

```gdscript
var id = ULID.generate()
print(id)  # "01KJDYPD0CY19AJERZ72YS5S65"
```

### With Registry

1. Copy both `ulid.gd` and `ulid_registry.gd` into your project
2. Register `ulid.gd` as Autoload `ULID`
3. Register `ulid_registry.gd` as Autoload `ULIDRegistry`
4. Load order doesn't matter — ULID detects the registry automatically after initialization

```gdscript
# Generate with metadata (auto-registered)
var id = ULID.generate("Hydrogen Extractor #1", "machine")

# Find all machines in creation order
var machines = ULIDRegistry.find_by_type("machine")

# Search by partial name
var results = ULIDRegistry.find_by_name_contains("Hydrogen")
```

## API — Core (ulid.gd)

### `generate(entry_name: String = "", entry_type: String = "") -> String`

Generate a new ULID. Returns a 26-character uppercase string. Monotonically increasing, lexicographically sortable.

If ULIDRegistry is loaded, the optional `entry_name` and `entry_type` are passed through for automatic registration. If the registry isn't loaded, these parameters are silently ignored.

```gdscript
var id1 = ULID.generate()
var id2 = ULID.generate("My Machine", "machine")
assert(id2 > id1)  # Always true
```

### `timestamp_of(ulid_str: String) -> int`

Extract the Unix timestamp in milliseconds from a ULID string.

```gdscript
var id = ULID.generate()
var ms = ULID.timestamp_of(id)
```

### `is_valid(ulid_str: String) -> bool`

Validate a ULID string. Checks length (26), character set (Crockford's Base32), and timestamp overflow (48-bit max).

```gdscript
ULID.is_valid("01KJDYPD0CY19AJERZ72YS5S65")  # true
ULID.is_valid("not-a-ulid")                     # false
```

### `has_registry() -> bool`

Check whether ULIDRegistry was detected at startup.

### `encode_b32(value: int, length: int) -> String`

Encode an integer to a fixed-length Crockford's Base32 string.

```gdscript
ULID.encode_b32(1000, 4)  # "00Z8"
```

### `decode_b32(encoded: String) -> int`

Decode a Crockford's Base32 string to an integer. Case-insensitive. Tolerates common substitutions (I/L -> 1, O -> 0) and strips hyphens.

```gdscript
ULID.decode_b32("00Z8")  # 1000
ULID.decode_b32("00z8")  # 1000
```

## API — Registry (ulid_registry.gd)

### Registration

| Method | Description |
|--------|-------------|
| `register(ulid, name?, type?) -> bool` | Register a ULID. Returns false if duplicate. Called automatically by `ULID.generate()` when the registry is loaded. |
| `unregister(ulid) -> bool` | Remove a ULID. Returns false if not found. |

### Lookup

| Method | Description |
|--------|-------------|
| `exists(ulid) -> bool` | Check if a ULID is registered. |
| `get_entry(ulid) -> Dictionary` | Full metadata: `{ "name", "type", "registered_at" }`. Returns empty Dictionary if not found. |
| `get_name(ulid) -> String` | Name of a registered ULID, or `""`. |
| `get_type(ulid) -> String` | Type tag of a registered ULID, or `""`. |

### Search

| Method | Description |
|--------|-------------|
| `find_by_type(type, sorted?) -> Array` | All ULIDs with the given type. Sorted by creation order by default. |
| `find_by_name(name) -> Array` | All ULIDs with the exact name. Sorted by creation order. |
| `find_by_name_contains(term) -> Array` | All ULIDs whose names contain the term (case-insensitive). |
| `get_all_types() -> Array` | All type tags currently in use. |
| `get_all(sorted?) -> Array` | All registered ULIDs. |

### Metadata Updates

| Method | Description |
|--------|-------------|
| `set_name(ulid, new_name) -> bool` | Update the name. Automatically updates the name index. |
| `set_type(ulid, new_type) -> bool` | Update the type tag. Automatically updates the type index. |

### Statistics

| Method | Description |
|--------|-------------|
| `count() -> int` | Total registered ULIDs. |
| `count_by_type(type) -> int` | Count of ULIDs with the given type. |
| `get_stats() -> Dictionary` | Summary: `{ "total": int, "types": { type: count } }`. |

### Serialization

| Method | Description |
|--------|-------------|
| `serialize() -> Dictionary` | Export the registry for save files. |
| `deserialize(data) -> void` | Import a saved registry, replacing current contents. Rebuilds all indices. |
| `clear() -> void` | Empty the registry. Call before `deserialize()` when loading saves. |

## ULID Structure

```
 01KJDYPD0C      Y19AJERZ72YS5S65
|----------|    |----------------|
 Timestamp          Randomness
  48 bits            80 bits
  10 chars           16 chars
```

**Timestamp**: Milliseconds since Unix epoch in Crockford's Base32. Won't overflow until the year 10889.

**Randomness**: 80 bits of cryptographically secure random data. Incremented within the same millisecond for monotonic ordering.

```gdscript
var ids = []
for i in range(100):
    ids.append(ULID.generate())

var sorted_ids = ids.duplicate()
sorted_ids.sort()
assert(ids == sorted_ids)  # Already sorted on creation
```

## Usage Examples

### Entity Identity

```gdscript
class_name BaseMachine
extends Node2D

var machine_ulid: String = ""

func _ready():
    if machine_ulid == "":
        machine_ulid = ULID.generate(machine_name, "machine")
```

### Save / Load

```gdscript
# Save
func save_game() -> Dictionary:
    return {
        "entities": {
            machine.machine_ulid: machine.serialize()
            # ...
        },
        "registry": ULIDRegistry.serialize()
    }

# Load
func load_game(data: Dictionary):
    ULIDRegistry.clear()
    ULIDRegistry.deserialize(data["registry"])

    # Entity keys are ULIDs — sorting gives creation order
    var entity_keys = data["entities"].keys()
    entity_keys.sort()
    for key in entity_keys:
        spawn_entity(data["entities"][key])
```

### Debug / Inspection

```gdscript
# How many of each type do I have?
var stats = ULIDRegistry.get_stats()
print(stats)  # { "total": 347, "types": { "machine": 42, "pipe": 198, "connection": 107 } }

# Find everything the player named "Bob"
var bobs = ULIDRegistry.find_by_name_contains("Bob")
```

## When to Use the Registry

The ULID core is useful for any Godot project that needs unique, sortable identifiers: save systems, multiplayer, entity tracking, undo/redo, modding support.

The registry is a convenience layer for projects that want quick entity tracking without building a custom system. It works well for prototyping, game jams, small-to-medium projects, and as a reference implementation of indexed entity lookup in GDScript. 

Larger projects will likely want entity tracking integrated with their own architecture (scene tree management, ECS, networking) rather than a standalone generic registry. The registry is designed to be easy to outgrow: if you eventually replace it with something project-specific, the ULID core continues to work unchanged.

## Design Decisions

**Byte-array randomness**: GDScript's `int` is 64-bit signed. The 80-bit random component doesn't fit. Rather than splitting into two integers and handling boundary encoding math, this implementation keeps the randomness as a `PackedByteArray` and encodes directly using a bit-stream accumulator. Incrementing for monotonicity is a byte-by-byte carry propagation. No integer overflow possible.

**Deferred registry detection**: ULID detects ULIDRegistry via `call_deferred("_detect_registry")` in `_ready()`. This ensures all Autoloads are initialized before the check runs, regardless of load order in Project Settings.

**Dual-index registry**: The registry maintains both a type index and a name index alongside the primary entries dictionary. This makes `find_by_type()` and `find_by_name()` O(1) lookups rather than O(n) scans. The tradeoff is slightly more bookkeeping on register/unregister/update, but lookups vastly outnumber mutations in typical usage.

**Crockford's Base32**: This is not RFC 4648 Base32. The alphabets are different. Crockford's excludes I, L, O, U to avoid visual ambiguity. Do not use built-in or third-party Base32 libraries, as they will produce incorrect output.

## Requirements

- Godot 4.0+
- No plugins or external dependencies

## Running Tests

Both files include a `run_tests()` method. Call from any script:

```gdscript
func _ready():
    ULID.run_tests()
    ULIDRegistry.run_tests()  # Only if registry is loaded
```

Check the Output panel for results. Remove test calls before shipping.

## License

MIT

## Acknowledgments

- [ULID Spec](https://github.com/ulid/spec) by Alizain Feerasta
- [Crockford's Base32](https://www.crockford.com/base32.html) by Douglas Crockford
