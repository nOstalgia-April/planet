@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "PlanetFMODBanks"


func _export_begin(
	_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int
) -> void:
	# Match the bank database's configured, flat bank directory. The native
	# exporter scans the whole project, including ignored output/ backups.
	var banks_root: String = ProjectSettings.get_setting("Fmod/General/banks_path", "")
	assert(banks_root.begins_with("res://") and banks_root != "res://")
	assert(DirAccess.dir_exists_absolute(banks_root))
	for file_name: String in DirAccess.get_files_at(banks_root):
		if file_name.ends_with(".bank"):
			var bank_path: String = banks_root.path_join(file_name)
			var data: PackedByteArray = FileAccess.get_file_as_bytes(bank_path)
			assert(not data.is_empty(), "Cannot export FMOD bank: " + bank_path)
			add_file(bank_path, data, false)
