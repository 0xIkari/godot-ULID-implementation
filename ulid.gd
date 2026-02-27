extends Node

# This will be my attempt at a ULID implementation
# Made by 0xIkari 
# v1.0.0

const CROCKFORD_ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

# State
var _last_timestamp: int = 0
var _rand_bytes: PackedByteArray = PackedByteArray()
var _crypto: Crypto = Crypto.new()

func encode_b32(value: int, length: int) -> String:
	# The algorithm:
	# 1. Take the value modulo 32 to get the least significant 5 bits
	# 2. Look up that value in the alphabet to get the character
	# 3. Integer-divide the value by 32 to shift right by 5 bits
	# 4. Repeat until you've filled the required length
	# 5. The characters come out in reverse order (least significant first),
	#    so reverse the result
	var chars: PackedStringArray = []
	for i in range(length):
		var index = value % 32
		chars.append(CROCKFORD_ALPHABET[index])
		value >>= 5
	chars.reverse()
	return ''.join(PackedStringArray(chars))
	
func decode_b32(encoded: String) -> int:
	var value: int = 0
	var clean_string = encoded.replace("-","").to_upper()
	for i in range(clean_string.length()):
		var char_to_find = clean_string[i]
		if char_to_find == "O": char_to_find = "0"
		elif char_to_find == "I" or char_to_find == "L": char_to_find = "1"
		var char_index = CROCKFORD_ALPHABET.find(char_to_find)
		if char_index == -1:
			push_error("Invalid character in Crockford String: " + char_to_find)
			return -1
		value = (value * 32) + char_index
	return value
	
func _get_timestamp_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _generate_fresh_random() -> void:
	_rand_bytes = _crypto.generate_random_bytes(10)

func _increment_random() -> void:
	# Add 1 to a big-endian byte array, with carry propagation.
	# Start from the rightmost byte (least significant), add 1.
	# If it overflows 255, reset to 0 and carry to the next byte left.
	# Identical to how you'd add 1 to a number by hand in base 256.
	for i in range(_rand_bytes.size() - 1, -1, -1):
		if _rand_bytes[i] < 255:
			_rand_bytes[i] += 1
			return
		_rand_bytes[i] = 0
	# If we get here, all 10 bytes were 0xFF and we overflowed.
	push_error("ULID random component overflow")
	
func timestamp_of(ulid_str: String) -> int:
	# Extract the millisecond timestamp from a ULID string.
	# The timestamp is the first 10 characters.
	return decode_b32(ulid_str.substr(0, 10))
	
func _encode_random() -> String:
	# 10 bytes = 80 bits = exactly 16 five-bit groups.
	# Extract 5-bit groups by treating the byte array as a bit stream.
	var chars: Array = []
	var buffer: int = 0    # Holds accumulated bits (never exceeds ~13 bits)
	var bits_in_buffer: int = 0
	
	for byte_val in _rand_bytes:
		buffer = (buffer << 8) | byte_val   # Push 8 new bits in
		bits_in_buffer += 8
		
		while bits_in_buffer >= 5:
			bits_in_buffer -= 5
			var index: int = (buffer >> bits_in_buffer) & 0x1F
			chars.append(CROCKFORD_ALPHABET[index])
	
	# 80 bits / 5 = exactly 16 characters, no remainder
	return "".join(PackedStringArray(chars))

func is_valid(ulid_str: String) -> bool:
	# 1. Length check
	if ulid_str.length() != 26:
		return false
	
	var clean_ulid = ulid_str.to_upper()
	
	# 2. Character validity check
	for i in range(clean_ulid.length()):
		if CROCKFORD_ALPHABET.find(clean_ulid[i]) == -1:
			return false
	
	# 3. 48-bit Overflow check (Timestamp portion)
	# Per ULID spec, the max timestamp is 2^48 - 1. 
	# In Base32, the first character must be '7' or less.
	if CROCKFORD_ALPHABET.find(clean_ulid[0]) > 7:
		return false
		
	return true
	
func generate() -> String:
	var current_ms = _get_timestamp_ms()
	
	# Monotonicity logic
	if current_ms > _last_timestamp:
		_last_timestamp = current_ms
		_generate_fresh_random()
	else:
		_increment_random()
	
	# 10 characters for timestamp (48 bits)
	var ts_part = encode_b32(_last_timestamp, 10)
	
	# 16 characters for randomness (80 bits)
	var rand_part = _encode_random()
	
	return ts_part + rand_part

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var my_ulid = generate()
	print("TEST: Generated ULID: ", my_ulid)
	print("TEST: Is valid? ", is_valid(my_ulid))
	print("TEST: Extracted Timestamp: ", timestamp_of(my_ulid))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
