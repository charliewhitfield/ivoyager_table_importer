# editor_plugin.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
@tool
extends EditorPlugin

# Adds a custom resource, an EditorImportPlugin, and autoload singletons
# specified by 'res://addons/ivoyager_table_importer/table_importer.cfg' and/or
# 'res://ivoyager_override.cfg'.
#
# All table data interface is through singleton 'IVTableData'
# (singletons/table_data.gd).
#
# Note: There is talk in Godot issues of depreciating 'add_custom_type()'.
# We prefer this method over file 'class_name' because it does not involve
# .godot/global_script_class_cache.cfg, which is buggy as of Godot 4.1.1 (fails
# to update changes outside of editor; we'll open an issue if this isn't fixed
# in 4.2-beta builds).

const plugin_utils := preload("plugin_utils.gd")
const TableResource := preload("table_resource.gd")
const EditorImportPluginClass := preload("editor_import_plugin.gd")

var _config: ConfigFile # base config with overrides
var _editor_import_plugin: EditorImportPlugin
var _autoloads := {}



func _enter_tree():
	plugin_utils.print_plugin_name_and_version("res://addons/ivoyager_table_importer/plugin.cfg",
			" - https://ivoyager.dev")
	_config = plugin_utils.get_config_with_override(
			"res://addons/ivoyager_table_importer/table_importer.cfg",
			"res://ivoyager_override.cfg", "res://ivoyager_override2.cfg")
	if !_config:
		return
	add_custom_type("IVTableResource", "Resource", TableResource, _get_table_resource_icon())
	_editor_import_plugin = EditorImportPluginClass.new()
	add_import_plugin(_editor_import_plugin)
	_add_autoloads()


func _exit_tree():
	print("Removing I, Voyager - Table Importer (plugin)")
	_config = null
	remove_custom_type("IVTableResource")
	remove_import_plugin(_editor_import_plugin)
	_editor_import_plugin = null
	_remove_autoloads()


func _get_table_resource_icon() -> Texture2D:
	var editor_gui := get_editor_interface().get_base_control()
	return editor_gui.get_theme_icon("Grid", "EditorIcons")


func _add_autoloads() -> void:
	for autoload_name in _config.get_section_keys("table_importer_autoload"):
		var value: Variant = _config.get_value("table_importer_autoload", autoload_name)
		if value: # could be null or "" to negate
			assert(typeof(value) == TYPE_STRING,
					"'%s' must specify a path as String" % autoload_name)
			_autoloads[autoload_name] = value
	for autoload_name in _autoloads:
		var path: String = _autoloads[autoload_name]
		add_autoload_singleton(autoload_name, path)


func _remove_autoloads() -> void:
	for autoload_name in _autoloads:
		remove_autoload_singleton(autoload_name)
	_autoloads.clear()

