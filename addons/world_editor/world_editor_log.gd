class_name WorldEditorLog
extends RefCounted

## Editor diagnostics for the World workbench.
##
## The workbench has no separate problems panel: errors and warnings go to the
## editor Output panel as `[World Editor][ERROR] message` / `[WARNING] message`.

const PREFIX := "[World Editor]"


static func format_error(message: String) -> String:
    return "%s[ERROR] %s" % [PREFIX, message]


static func format_warning(message: String) -> String:
    return "%s[WARNING] %s" % [PREFIX, message]


static func format_info(message: String) -> String:
    return "%s[INFO] %s" % [PREFIX, message]


static func error(message: String) -> void:
    print(format_error(message))


static func warning(message: String) -> void:
    print(format_warning(message))


static func info(message: String) -> void:
    print(format_info(message))
