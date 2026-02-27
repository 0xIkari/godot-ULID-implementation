# ulid_registry.gd - ULID Registry Autoload Singleton
# Register as Autoload named "ULIDRegistry" in Project Settings > Globals
#
# Provides a centralized registry for tracking ULIDs with optional names
# and type tags. Supports lookup by ULID, search by name or type, and
# chronological sorting (which is just alphabetical sorting, because ULIDs).
#
# This autoload is OPTIONAL. The ULID autoload works without it.
# When both are loaded, ULID.generate() auto-registers entries here.
extends Node


# =============================================================================
# DATA STRUCTURE
# =============================================================================
#
# The registry is a Dictionary keyed by ULID string.
# Each value is a Dictionary with the entry's metadata:
#
#   {
#       "name": String,         # Human-readable name (empty string if unnamed)
#       "type": String,         # Type tag for categorized lookup (empty if untyped)
#       "registered_at": int,   # Timestamp in ms when registered (from the ULID itself)
#   }
#
# A second Dictionary provides reverse lookup from type -> Array of ULIDs,
# so type-based queries don't require scanning the entire registry.

var _entries: Dictionary = {}
var _type_index: Dictionary = {}    # type_string -> Array[String] of ULIDs
var _name_index: Dictionary = {}    # name_string -> Array[String] of ULIDs


# =============================================================================
# REGISTRATION
# =============================================================================

func register(ulid_str: String, entry_name: String = "", entry_type: String = "") -> bool:
	## Register a ULID in the registry with optional name and type.
	##
	## Returns true if registered successfully, false if the ULID already exists.
	## Duplicate ULIDs are rejected — this should never happen with correct
	## generation, but the check exists as a safety net.
	if _entries.has(ulid_str):
		push_warning("ULIDRegistry: Duplicate ULID rejected: %s" % ulid_str)
		return false

	# Extract timestamp from the ULID itself rather than checking the clock,
	# so the registered_at value is consistent with the ULID's embedded time.
	var timestamp: int = 0
	var ulid_node = get_node_or_null("/root/ULID")
	if ulid_node:
		timestamp = ulid_node.timestamp_of(ulid_str)

	_entries[ulid_str] = {
		"name": entry_name,
		"type": entry_type,
		"registered_at": timestamp,
	}

	# Update type index
	if entry_type != "":
		if not _type_index.has(entry_type):
			_type_index[entry_type] = []
		_type_index[entry_type].append(ulid_str)

	# Update name index
	if entry_name != "":
		if not _name_index.has(entry_name):
			_name_index[entry_name] = []
		_name_index[entry_name].append(ulid_str)

	return true


func unregister(ulid_str: String) -> bool:
	## Remove a ULID from the registry.
	## Returns true if found and removed, false if not found.
	if not _entries.has(ulid_str):
		return false

	var entry: Dictionary = _entries[ulid_str]

	# Remove from type index
	if entry["type"] != "" and _type_index.has(entry["type"]):
		_type_index[entry["type"]].erase(ulid_str)
		if _type_index[entry["type"]].is_empty():
			_type_index.erase(entry["type"])

	# Remove from name index
	if entry["name"] != "" and _name_index.has(entry["name"]):
		_name_index[entry["name"]].erase(ulid_str)
		if _name_index[entry["name"]].is_empty():
			_name_index.erase(entry["name"])

	_entries.erase(ulid_str)
	return true


# =============================================================================
# UPDATE METADATA
# =============================================================================

func set_ulid_name(ulid_str: String, new_name: String) -> bool:
	## Update the name of a registered ULID.
	## Returns false if the ULID is not registered.
	if not _entries.has(ulid_str):
		return false

	var old_name: String = _entries[ulid_str]["name"]

	# Remove from old name index
	if old_name != "" and _name_index.has(old_name):
		_name_index[old_name].erase(ulid_str)
		if _name_index[old_name].is_empty():
			_name_index.erase(old_name)

	# Set new name
	_entries[ulid_str]["name"] = new_name

	# Add to new name index
	if new_name != "":
		if not _name_index.has(new_name):
			_name_index[new_name] = []
		_name_index[new_name].append(ulid_str)

	return true


func set_type(ulid_str: String, new_type: String) -> bool:
	## Update the type tag of a registered ULID.
	## Returns false if the ULID is not registered.
	if not _entries.has(ulid_str):
		return false

	var old_type: String = _entries[ulid_str]["type"]

	# Remove from old type index
	if old_type != "" and _type_index.has(old_type):
		_type_index[old_type].erase(ulid_str)
		if _type_index[old_type].is_empty():
			_type_index.erase(old_type)

	# Set new type
	_entries[ulid_str]["type"] = new_type

	# Add to new type index
	if new_type != "":
		if not _type_index.has(new_type):
			_type_index[new_type] = []
		_type_index[new_type].append(ulid_str)

	return true


# =============================================================================
# LOOKUP
# =============================================================================

func exists(ulid_str: String) -> bool:
	## Check if a ULID is registered.
	return _entries.has(ulid_str)


func get_entry(ulid_str: String) -> Dictionary:
	## Get the full metadata for a registered ULID.
	## Returns an empty Dictionary if not found.
	if _entries.has(ulid_str):
		return _entries[ulid_str].duplicate()  # Return copy, not reference
	return {}


func get_ulid_name(ulid_str: String) -> String:
	## Get the name of a registered ULID. Returns "" if not found or unnamed.
	if _entries.has(ulid_str):
		return _entries[ulid_str]["name"]
	return ""


func get_type(ulid_str: String) -> String:
	## Get the type tag of a registered ULID. Returns "" if not found or untyped.
	if _entries.has(ulid_str):
		return _entries[ulid_str]["type"]
	return ""


# =============================================================================
# SEARCH
# =============================================================================

func find_by_type(entry_type: String, sorted: bool = true) -> Array:
	## Get all ULIDs with the given type tag.
	## Returns them in creation order by default (sorted=true).
	## Since ULIDs are lexicographically sortable, creation order is just
	## alphabetical order.
	if not _type_index.has(entry_type):
		return []
	var results: Array = _type_index[entry_type].duplicate()
	if sorted:
		results.sort()
	return results


func find_by_name(entry_name: String) -> Array:
	## Get all ULIDs with the given name.
	## Multiple ULIDs can share a name (e.g., "Hydrogen Extractor").
	## Results returned in creation order.
	if not _name_index.has(entry_name):
		return []
	var results: Array = _name_index[entry_name].duplicate()
	results.sort()
	return results


func find_by_name_contains(search_term: String) -> Array:
	## Search for ULIDs whose names contain the search term (case-insensitive).
	## Useful for player-facing search functionality or debug consoles.
	var results: Array = []
	var term_lower: String = search_term.to_lower()
	for ulid_str in _entries:
		if _entries[ulid_str]["name"].to_lower().contains(term_lower):
			results.append(ulid_str)
	results.sort()
	return results


func get_all_types() -> Array:
	## Get a list of all type tags currently in use.
	return _type_index.keys()


func get_all(sorted: bool = true) -> Array:
	## Get all registered ULIDs.
	## Sorted by default (creation order).
	var results: Array = _entries.keys()
	if sorted:
		results.sort()
	return results


# =============================================================================
# STATISTICS
# =============================================================================

func count() -> int:
	## Total number of registered ULIDs.
	return _entries.size()


func count_by_type(entry_type: String) -> int:
	## Number of ULIDs with the given type tag.
	if _type_index.has(entry_type):
		return _type_index[entry_type].size()
	return 0


func get_stats() -> Dictionary:
	## Get a summary of registry contents.
	## Returns: { "total": int, "types": { type: count, ... } }
	var type_counts: Dictionary = {}
	for entry_type in _type_index:
		type_counts[entry_type] = _type_index[entry_type].size()
	return {
		"total": _entries.size(),
		"types": type_counts,
	}


# =============================================================================
# SERIALIZATION (for save/load)
# =============================================================================

func serialize() -> Dictionary:
	## Export the entire registry as a Dictionary suitable for JSON serialization.
	## Call this when saving.
	return _entries.duplicate(true)  # Deep copy


func deserialize(data: Dictionary) -> void:
	## Import a previously serialized registry, replacing current contents.
	## Call this when loading a save file.
	##
	## Rebuilds the type and name indices from the loaded data.
	_entries.clear()
	_type_index.clear()
	_name_index.clear()

	for ulid_str in data:
		var entry: Dictionary = data[ulid_str]
		_entries[ulid_str] = {
			"name": entry.get("name", ""),
			"type": entry.get("type", ""),
			"registered_at": entry.get("registered_at", 0),
		}

		# Rebuild type index
		var entry_type: String = _entries[ulid_str]["type"]
		if entry_type != "":
			if not _type_index.has(entry_type):
				_type_index[entry_type] = []
			_type_index[entry_type].append(ulid_str)

		# Rebuild name index
		var entry_name: String = _entries[ulid_str]["name"]
		if entry_name != "":
			if not _name_index.has(entry_name):
				_name_index[entry_name] = []
			_name_index[entry_name].append(ulid_str)


func clear() -> void:
	## Clear the entire registry. Use when starting a new game or loading
	## a save (call clear() then deserialize()).
	_entries.clear()
	_type_index.clear()
	_name_index.clear()


# =============================================================================
# TESTS (call ULIDRegistry.run_tests() from any script)
# =============================================================================

func run_tests() -> void:
	print("=== ULID REGISTRY TESTS ===")
	var ulid_node = get_node_or_null("/root/ULID")
	if not ulid_node:
		push_error("ULIDRegistry tests require ULID autoload")
		return
	ulid_node._detect_registry()

	# Clean slate
	var pre_count: int = count()

	# Test: basic registration
	var id1: String = ulid_node.generate("Alpha Machine", "machine")
	var id2: String = ulid_node.generate("Beta Machine", "machine")
	var id3: String = ulid_node.generate("Main Pipe", "pipe")
	var id4: String = ulid_node.generate("", "connection")  # No name
	var id5: String = ulid_node.generate()  # No name or type
	assert(exists(id1), "Registered ULID not found")
	assert(exists(id5), "Bare ULID not found")
	print("PASS: basic registration")

	# Test: lookup
	assert(get_ulid_name(id1) == "Alpha Machine", "Name lookup failed")
	assert(get_type(id3) == "pipe", "Type lookup failed")
	assert(get_ulid_name(id4) == "", "Unnamed entry returned a name")
	print("PASS: lookup")

	# Test: find by type
	var machines: Array = find_by_type("machine")
	assert(machines.size() >= 2, "Type search returned too few results")
	assert(id1 in machines, "Machine 1 not in type results")
	assert(id2 in machines, "Machine 2 not in type results")
	assert(id3 not in machines, "Pipe incorrectly in machine results")
	print("PASS: find_by_type (%d machines)" % machines.size())

	# Test: find by type returns sorted (creation order)
	assert(machines[machines.find(id1)] < machines[machines.find(id2)],
		"Type results not in creation order")
	print("PASS: type results sorted by creation order")

	# Test: find by name
	var alphas: Array = find_by_name("Alpha Machine")
	assert(alphas.size() >= 1, "Name search returned no results")
	assert(id1 in alphas, "Alpha not in name results")
	print("PASS: find_by_name")

	# Test: name contains search
	var pipe_search: Array = find_by_name_contains("pipe")
	assert(id3 in pipe_search, "Pipe not found in contains search")
	print("PASS: find_by_name_contains")

	# Test: update metadata
	set_ulid_name(id1, "Renamed Machine")
	assert(get_ulid_name(id1) == "Renamed Machine", "Name update failed")
	assert(find_by_name("Alpha Machine").size() == 0 or id1 not in find_by_name("Alpha Machine"),
		"Old name index not cleaned up")
	assert(id1 in find_by_name("Renamed Machine"), "New name index not updated")
	print("PASS: set_ulid_name")

	set_type(id3, "conveyor")
	assert(get_type(id3) == "conveyor", "Type update failed")
	assert(id3 not in find_by_type("pipe"), "Old type index not cleaned up")
	assert(id3 in find_by_type("conveyor"), "New type index not updated")
	print("PASS: set_type")

	# Test: stats
	var stats: Dictionary = get_stats()
	assert(stats["total"] >= 5, "Stats total too low")
	assert(stats["types"].has("machine"), "Stats missing machine type")
	print("PASS: get_stats (total: %d, types: %s)" % [stats["total"], str(stats["types"])])

	# Test: serialization round-trip
	var serialized: Dictionary = serialize()
	var original_count: int = count()
	clear()
	assert(count() == 0, "Clear didn't empty registry")
	deserialize(serialized)
	assert(count() == original_count, "Deserialize count mismatch: %d != %d" % [count(), original_count])
	assert(exists(id1), "Entry lost after serialize/deserialize")
	assert(get_ulid_name(id1) == "Renamed Machine", "Name lost after serialize/deserialize")
	assert(id3 in find_by_type("conveyor"), "Type index not rebuilt after deserialize")
	print("PASS: serialize/deserialize round-trip")

	# Test: unregister
	var pre_unregister: int = count()
	assert(unregister(id5), "Unregister returned false")
	assert(not exists(id5), "Unregistered ULID still found")
	assert(count() == pre_unregister - 1, "Count didn't decrease after unregister")
	print("PASS: unregister")

	# Test: duplicate rejection
	assert(not register(id1), "Duplicate ULID was accepted")
	print("PASS: duplicate rejection")

	# Cleanup test entries
	unregister(id1)
	unregister(id2)
	unregister(id3)
	unregister(id4)

	print("=== ALL REGISTRY TESTS PASSED ===")
