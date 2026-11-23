extends Node

## Static hygiene guard for the whole project.
##
## Reproduces the GDScript analyzer checks that are easy to regress by hand and
## that the editor only shows while it recompiles a script:
##
## 1. A local, parameter or member named after a property of the script's own
##    base class (`position`, `material`, `modulate`, ...) shadows that property.
## 2. A function parameter that is never read (prefix it with `_` if unused).
##
## The base class is resolved through `extends` chains (including class_name
## scripts), and the property names come from `ClassDB`, so a local named `size`
## in a `RefCounted` is not reported while one in a `Control` is.

const ROOT := "res://"
const SKIP_DIRECTORIES: Array[String] = ["res://.godot", "res://.tmp"]

## Built-in functions whose name a script must not reuse (`SHADOWED_GLOBAL_IDENTIFIER`).
const BUILTIN_NAMES: Array[String] = [
	"seed", "randi", "randf", "randi_range", "randf_range", "rand_from_seed",
	"print", "printerr", "print_rich", "prints", "push_error", "push_warning",
	"range", "load", "preload", "assert", "str",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var classes := _global_classes()
	var scripts := _collect_scripts()
	if scripts.is_empty():
		return ["script hygiene scan found no scripts"]
	for path: String in scripts:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var base := _resolve_base_class(path, text, classes)
		if not base.is_empty():
			var properties := _base_properties(base)
			failures.append_array(_check_shadowing(path, text, properties))
		failures.append_array(_check_unused_parameters(path, text))
		failures.append_array(_check_builtin_shadowing(path, text))
	return failures


func _collect_scripts() -> Array[String]:
	var scripts: Array[String] = []
	var pending: Array[String] = [ROOT]
	while not pending.is_empty():
		var directory_path: String = pending.pop_back()
		if SKIP_DIRECTORIES.has(directory_path):
			continue
		var directory := DirAccess.open(directory_path)
		if directory == null:
			continue
		directory.list_dir_begin()
		while true:
			var entry_name := directory.get_next()
			if entry_name.is_empty():
				break
			if entry_name.begins_with("."):
				continue
			var path := directory_path.path_join(entry_name)
			if directory.current_is_dir():
				pending.append(path)
			elif path.get_extension().to_lower() == "gd":
				scripts.append(path)
		directory.list_dir_end()
	scripts.sort()
	return scripts


## class_name -> {path, base} from the project's registered global classes.
func _global_classes() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var class_name_text := String(entry.get("class", ""))
		if class_name_text.is_empty():
			continue
		result[class_name_text] = {
			"path": String(entry.get("path", "")),
			"base": String(entry.get("base", "")),
		}
	return result


## Walks `extends` until a real engine class, or "" when it cannot be resolved.
func _resolve_base_class(path: String, text: String, classes: Dictionary, depth: int = 0) -> String:
	if depth > 12:
		return ""
	var extends_line := _find_extends(text)
	if extends_line.is_empty():
		return ""
	var target := extends_line.strip_edges()
	if target.begins_with("\"") or target.begins_with("'"):
		target = target.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	if target.begins_with("res://"):
		if not FileAccess.file_exists(target):
			return ""
		var parent_text := FileAccess.get_file_as_string(target)
		return _resolve_base_class(target, parent_text, classes, depth + 1)
	if ClassDB.class_exists(target):
		return target
	if classes.has(target):
		var entry: Dictionary = classes[target]
		var entry_base := String(entry.get("base", ""))
		if entry_base == "Resource" or entry_base == "RefCounted" or entry_base == "Object":
			return entry_base
		var entry_path := String(entry.get("path", ""))
		if entry_path.is_empty() or not FileAccess.file_exists(entry_path):
			return entry_base
		return _resolve_base_class(entry_path, FileAccess.get_file_as_string(entry_path), classes, depth + 1)
	# `extends "SomeClass"` with a class_name that is not registered yet.
	return target if ClassDB.class_exists(target) else ""


func _find_extends(text: String) -> String:
	for line: String in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("extends "):
			return stripped.substr(8).strip_edges()
	return ""


func _base_properties(base: String) -> Dictionary:
	var properties: Dictionary = {}
	if base.is_empty() or not ClassDB.class_exists(base):
		return properties
	for property: Dictionary in ClassDB.class_get_property_list(base, true):
		var property_name := String(property.get("name", ""))
		if not property_name.is_empty():
			properties[property_name] = true
	return properties


func _check_shadowing(path: String, text: String, properties: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if properties.is_empty():
		return failures
	var lines := text.split("\n")
	var declaration := RegEx.create_from_string(
		"^\\s*(?:var\\s+|for\\s+|const\\s+)?([A-Za-z_][A-Za-z0-9_]*)\\s*(?::|:=|\\bin\\b|=)"
	)
	var parameter := RegEx.create_from_string("(?:^|[(,])\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(?::|,|\\)|=)")
	for index: int in range(lines.size()):
		var line := lines[index]
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or stripped.is_empty():
			continue
		var candidates: Array[String] = []
		if stripped.begins_with("var ") or stripped.begins_with("for ") or stripped.begins_with("const "):
			var match := declaration.search(line)
			if match != null:
				candidates.append(match.get_string(1))
		elif stripped.begins_with("func ") or (stripped.begins_with("static func ")):
			var open := line.find("(")
			var close := line.find(")", open)
			if open >= 0 and close > open:
				var arguments := line.substr(open, close - open + 1)
				for match: RegExMatch in parameter.search_all(arguments):
					candidates.append(match.get_string(1))
		for candidate: String in candidates:
			if not properties.has(candidate):
				continue
			failures.append(
				"%s:%d shadows the base class property \"%s\"; rename it"
				% [path, index + 1, candidate]
			)
	return failures


## Declarations that reuse a built-in function name, e.g. `func f(seed)`.
func _check_builtin_shadowing(path: String, text: String) -> Array[String]:
	var failures: Array[String] = []
	var declaration := RegEx.create_from_string(
		"^\\s*(?:var\\s+|for\\s+|const\\s+)?([A-Za-z_][A-Za-z0-9_]*)\\s*(?::|:=|\\bin\\b|=)"
	)
	var parameter := RegEx.create_from_string("(?:^|[(,])\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(?::|,|\\)|=)")
	var lines := text.split("\n")
	for index: int in range(lines.size()):
		var line := lines[index]
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or stripped.is_empty():
			continue
		var candidates: Array[String] = []
		if stripped.begins_with("var ") or stripped.begins_with("for ") or stripped.begins_with("const "):
			var match := declaration.search(line)
			if match != null:
				candidates.append(match.get_string(1))
		elif stripped.begins_with("func ") or stripped.begins_with("static func "):
			var open := line.find("(")
			var close := line.find(")", open)
			if open >= 0 and close > open:
				for match: RegExMatch in parameter.search_all(line.substr(open, close - open + 1)):
					candidates.append(match.get_string(1))
		for candidate: String in candidates:
			if not BUILTIN_NAMES.has(candidate):
				continue
			failures.append(
				"%s:%d reuses the built-in name \"%s\"; rename it" % [path, index + 1, candidate]
			)
	return failures


func _check_unused_parameters(path: String, text: String) -> Array[String]:
	var failures: Array[String] = []
	var lines := text.split("\n")
	var signature := RegEx.create_from_string("^\\s*(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\((.*)\\)")
	var parameter := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*(?::|,|$)")
	var word := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
	for index: int in range(lines.size()):
		var match := signature.search(lines[index])
		if match == null:
			continue
		var function_name := match.get_string(1)
		var arguments := match.get_string(2)
		var names: Array[String] = []
		for argument: String in arguments.split(","):
			var cleaned := argument.strip_edges()
			if cleaned.is_empty():
				continue
			var name_match := parameter.search(cleaned)
			if name_match == null:
				continue
			var argument_name := name_match.get_string(1)
			if argument_name.begins_with("_"):
				continue
			if argument_name == "void":
				continue
			names.append(argument_name)
		if names.is_empty():
			continue
		var body := _function_body(lines, index)
		for argument_name: String in names:
			if _count_word(body, argument_name) == 0:
				failures.append(
					"%s:%d parameter \"%s\" of %s() is never used; prefix it with _ or remove it"
					% [path, index + 1, argument_name, function_name]
				)
	return failures


## Lines after the signature until the next `func` at the same or lower indent.
func _function_body(lines: PackedStringArray, signature_index: int) -> String:
	var indent := _indent_of(lines[signature_index])
	var body: Array[String] = []
	for index: int in range(signature_index + 1, lines.size()):
		var line := lines[index]
		if line.strip_edges().is_empty():
			continue
		var next_indent := _indent_of(line)
		if next_indent <= indent and line.strip_edges().begins_with("func "):
			break
		if next_indent <= indent and next_indent == 0 and not line.strip_edges().begins_with("#"):
			break
		body.append(line)
	return "\n".join(body)


func _indent_of(line: String) -> int:
	var indent := 0
	for character: String in line:
		if character == " ":
			indent += 1
		elif character == "\t":
			indent += 4
		else:
			break
	return indent


func _count_word(text: String, word: String) -> int:
	var count := 0
	var cursor := 0
	while true:
		var found := text.find(word, cursor)
		if found < 0:
			break
		var before_ok := found == 0 or not _is_identifier_char(text[found - 1])
		var after := found + word.length()
		var after_ok := after >= text.length() or not _is_identifier_char(text[after])
		if before_ok and after_ok:
			count += 1
		cursor = found + 1
	return count


static func _is_identifier_char(character: String) -> bool:
	return character == "_" or (character >= "0" and character <= "9") \
		or (character >= "a" and character <= "z") \
		or (character >= "A" and character <= "Z") or character.unicode_at(0) > 127
