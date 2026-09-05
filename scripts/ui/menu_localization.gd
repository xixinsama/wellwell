class_name WellwellMenuLocalization
extends Node

const CATALOG_PATH := "res://localization/menu.csv"

var _translations: Array[Translation] = []

func _enter_tree() -> void:
    return
    #load_catalog()

func load_catalog() -> bool:
    for translation: Translation in _translations:
        TranslationServer.remove_translation(translation)
    _translations.clear()

    var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
    if file == null:
        push_error("Could not open menu translation catalog: %s" % CATALOG_PATH)
        return false
    var header := file.get_csv_line()
    if header.size() < 2 or header[0] != "keys":
        file.close()
        push_error("Menu translation catalog has an invalid header.")
        return false

    for column: int in range(1, header.size()):
        var translation := Translation.new()
        translation.locale = header[column]
        _translations.append(translation)

    while not file.eof_reached():
        var row := file.get_csv_line()
        if row.is_empty() or row[0].is_empty():
            continue
        for column: int in range(1, mini(row.size(), header.size())):
            _translations[column - 1].add_message(row[0], row[column])
    file.close()

    for translation: Translation in _translations:
        TranslationServer.add_translation(translation)
    return true
