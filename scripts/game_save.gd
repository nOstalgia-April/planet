extends RefCounted

const VERSION: int = 1
const MAX_BYTES: int = 16 * 1024 * 1024
const MAGIC: String = "PlanetSave"

# The menu authorizes persistence for the formal game. F6 previews and checks never
# read or overwrite a player's slot merely by instantiating the gameplay scene.
static var session_requested: bool = false
static var pending_snapshot: Dictionary = {}
static var save_path: String = "user://planet.save"


static func load_latest() -> Dictionary:
	var snapshot: Dictionary = _read(save_path)
	if snapshot.is_empty():
		snapshot = _read(save_path + ".bak")
	return snapshot


static func write(snapshot: Dictionary, new_run: bool = false) -> Error:
	var payload: PackedByteArray = var_to_bytes(snapshot)
	var envelope: Dictionary = {
		"magic": MAGIC,
		"version": VERSION,
		"payload": payload,
		"digest": _digest(payload),
	}
	var temporary: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(envelope)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return error
	if _read(temporary).is_empty():
		return ERR_FILE_CORRUPT
	# Keep the last valid copy, including when the primary was damaged.
	if not _read(save_path).is_empty():
		error = DirAccess.copy_absolute(save_path, save_path + ".bak")
		if error != OK:
			return error
	# Godot's rename replaces an existing destination on supported desktop platforms.
	error = DirAccess.rename_absolute(temporary, save_path)
	if error == OK and new_run:
		# An explicit restart must never fall back to the abandoned run.
		error = DirAccess.copy_absolute(save_path, save_path + ".bak")
	return error


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES or file.get_length() < 4:
		return {}
	var encoded_length: int = file.get_32()
	if encoded_length != file.get_length() - 4:
		file.close()
		return {}
	file.seek(0)
	var envelope: Variant = file.get_var(false)
	file.close()
	if not envelope is Dictionary:
		return {}
	if envelope.get("magic") != MAGIC or envelope.get("version") != VERSION:
		return {}
	var payload: Variant = envelope.get("payload")
	if not payload is PackedByteArray or envelope.get("digest") != _digest(payload):
		return {}
	var snapshot: Variant = bytes_to_var(payload)
	if not snapshot is Dictionary:
		return {}
	for section: String in ["world", "story", "restoration", "discovery"]:
		if not snapshot.get(section) is Dictionary:
			return {}
	return snapshot


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()
