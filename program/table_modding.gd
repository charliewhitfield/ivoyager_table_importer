# table_modding.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVTableModding
extends RefCounted

## Enables easy user modding of tables (and optionally other files).
##
## Instantiate this class to enable easy user modding of tables or other files
## in 'user://modding/base_files/' and 'user://modding/mod_files/'
## (or other specified directories). The modding/base_files/ directory will
## contain read-only files for user to use as templates. Users will have access
## only to specified files. This class handles import of modded table files that
## users add to the modding/mod_files directory; you'll have to handle any other
## mod files with additional code.[br][br]
##
## (Don't confuse user modding with TableDirectives.DB_ENTITIES_MOD. That's for
## in-table changes to existing tables by projects or plugins.)[br][br]
##
## You probably only need to use the function 'process_modding_tables_and_files()'
## to do everything. It will call the other functions.[br][br]
##
## Functions here must be called before IVTableData.postprocess_tables().[br][br]
##
## Using this class in an editor run will create and populate a directory in
## your project (at 'res://unimported/' by default).
## The files in this directory are copies of modable files with added extension
## '.unimported' to protect them from Godot's import system. This is necessary
## for the modding system to work in export projects. See warning below for more
## details. You might want to add this directory or '*.unimported' to your
## .gitignore file.[br][br]
##
## WARNING: Two things are needed for export projects to work properly:
## 1. The project must be run at least once in the editor before export. This
##    will create and populate an 'unimported' directory in your project that
##    contains the moddable files (see comments above).
## 2. Add filter '*.unimported' (or a directory filter if you want) to
##    Project/Export/Resources/'Filters to export non-resource files/folders'.

const TableResource := preload("../editor_plugin/table_resource.gd")
const DEFAULT_BASE_FILES_README_TEXT := """Files are read-only!

To mod:
  * Copy the file to modding/mod_files/.
  * Open the copied file's properties and unset attribute 'Read-only'.
  * Mod away!

Don't modify files in THIS directory (modding/base_files/). If files are
are modified or moved by accident, delete the whole directory to force an
update.

WARNING! Bad mod data may cause errors or crash the application. To recover,
delete the problematic file(s) in modding/mod_files or delete the whole
directory.

Note: Most csv/tsv editors will change data without warning and without any
reasonable way to prevent it (e.g., "reformatting" text if it looks vaguely
like a date, truncating high-precision numbers, etc.). One editor that does
not do this is Rons Data Edit: https://www.ronsplace.ca/products/ronsdataedit.
"""


var _version: String
var _project_unimported_dir: String
var _modding_base_files_dir: String
var _modding_mod_files_dir: String
var _base_files_readme_text := DEFAULT_BASE_FILES_README_TEXT


## 'version' is used to test whether files in modding_base_files_dir are current
## and don't need to be replaced; they are always replaced if version == "".
## 'project_unimported_dir' will be created in your project to hold file copies
## protected from Godot import with exension '.unimported'.
func _init(version := "",
		project_unimported_dir := "res://unimported",
		modding_base_files_dir := "user://modding/base_files",
		modding_mod_files_dir := "user://modding/mod_files",
		base_files_readme_text := "<use default>") -> void:
	assert(project_unimported_dir)
	_project_unimported_dir = project_unimported_dir
	_version = version
	if modding_base_files_dir:
		_modding_base_files_dir = modding_base_files_dir
		DirAccess.make_dir_recursive_absolute(modding_base_files_dir)
	if modding_mod_files_dir:
		_modding_mod_files_dir = modding_mod_files_dir
		DirAccess.make_dir_recursive_absolute(modding_mod_files_dir)
	if base_files_readme_text != "<use default>":
		_base_files_readme_text = base_files_readme_text


## Use this function to do everything or call other functions individually.
## All tables can be specified in 'table_names' if you don't need subdirectories.
## Files specified in 'additional_file_original_paths' will be added to
## modding_base_files_dir and updated in parallel with table files.
## 'additional_file_base_paths' can optionally be supplied if you want additional
## files to be placed in subdirectories.
func process_modding_tables_and_files(original_table_paths: Array, table_names := [],
		table_base_paths := [], additional_file_original_paths := [],
		additional_file_base_paths := []) -> void:
	populate_project_unimported_dir(original_table_paths, table_names, table_base_paths,
			additional_file_original_paths)
	if !is_modding_base_files_current():
		add_modding_base_files(table_names, table_base_paths, additional_file_original_paths,
				additional_file_base_paths)
	import_modding_mod_files_tables(table_names, table_base_paths)


## Tables can be specified in either 'table_names' or 'table_base_paths'
## ('table_base_paths' is used in this function only to extract table names).
## Additional files can be specified by path in 'additional_file_original_paths'.
## Asserts if any duplicate file names occur.
## This function only runs in the editor; it does nothing in an exported project.
func populate_project_unimported_dir(original_table_paths: Array, table_names := [],
		table_base_paths := [], additional_file_original_paths := []) -> void:
	
	if !OS.has_feature("editor"):
		return
	
	DirAccess.make_dir_recursive_absolute(_project_unimported_dir)
	_remove_files_recursive(_project_unimported_dir, "unimported")
	
	# start with original paths for 'additional files'
	var original_paths := additional_file_original_paths.duplicate()
	# then append table original paths, which we have to find
	for name: String in table_names:
		var original_path := _get_original_table_path(name, original_table_paths)
		assert(original_path, "Did not find original path for table %s" % name)
		original_paths.append(original_path)
	for table_base_path: String in table_base_paths:
		var name := table_base_path.get_basename().get_file()
		var original_path := _get_original_table_path(name, original_table_paths)
		assert(original_path, "Did not find original path for table %s" % name)
		original_paths.append(original_path)
	
	# Copy from original path to unimported directory w/ added .unimported extension.
	# Note that DirAccess.copy_absolute()
	# only seems to work in editor run (as of Godot 4.3), but that's ok here.
	# Also test and assert duplicate file names.
	var file_names := []
	for original_path: String in original_paths:
		var file_name := original_path.get_file()
		assert(!file_names.has(file_name), "Attempt to add duplicate file name for modding")
		file_names.append(file_name)
		var copy_path := _project_unimported_dir.path_join(file_name + ".unimported")
		var err := DirAccess.copy_absolute(original_path, copy_path)
		assert(err == OK)


## Uses 'version' specified at _init().
func is_modding_base_files_current() -> bool:
	if !_version:
		return false
	var version_config := ConfigFile.new()
	var err := version_config.load(_modding_base_files_dir.path_join("version.cfg"))
	if err != OK:
		return false
	var existing_version: String = version_config.get_value("version", "version", "")
	return existing_version == _version


## Specify tables in either 'table_names' or 'table_base_paths'. Use the latter if
## you need to specify a destination different than 'modding_base_files_dir'.
## Table names are always the same as the file base names in the paths.
## 'additional_file_original_paths' should be the same supplied in
## populate_project_unimported_dir().
func add_modding_base_files(table_names := [], table_base_paths := [],
		additional_file_original_paths := [], additional_file_base_paths := []) -> void:
	_remove_files_recursive(_modding_base_files_dir, "")
	# destination paths for tables
	var base_paths := table_base_paths.duplicate()
	for table_name: String in table_names:
		var path := _modding_base_files_dir.path_join(table_name + ".tsv")
		base_paths.append(path)
	# destination paths for additional files
	base_paths.append_array(additional_file_base_paths)
	for additional_file_original_path: String in additional_file_original_paths:
		var file_name := additional_file_original_path.get_file()
		if !_is_file_in_paths_array(file_name, additional_file_base_paths):
			var path := _modding_base_files_dir.path_join(file_name)
			base_paths.append(path)
	
	# copy from unimported to modding/base_files
	for base_path: String in base_paths:
		if FileAccess.file_exists(base_path):
			FileAccess.set_read_only_attribute(base_path, false) # allows overwrite
		else:
			var base_dir := base_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(base_dir)
		var file_name := base_path.get_file()
		var source_path := _project_unimported_dir.path_join(file_name + ".unimported")
		
		# Godot 4.3 ISSUE: DirAccess.copy_absolute(source_path, path) fails
		# with read error in export project, even though below works...
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		var source_content := source_file.get_as_text()
		var write_file := FileAccess.open(base_path, FileAccess.WRITE)
		write_file.store_string(source_content)
		
		FileAccess.set_read_only_attribute(base_path, true)
	
	if _base_files_readme_text:
		var readme := FileAccess.open(_modding_base_files_dir.path_join("README.txt"),
				FileAccess.WRITE)
		readme.store_string(_base_files_readme_text)
	
	var version_config := ConfigFile.new()
	version_config.set_value("version", "version", _version)
	version_config.save(_modding_base_files_dir.path_join("version.cfg"))


## Tables can be specified in either 'table_names' or 'table_base_paths'
## ('table_base_paths' is used in this function only to extract table names).
## Subdirectory nesting structure doesn't matter at all to this function. User
## might parallel modding/base_files subdirectories (if they are present), but
## they don't have to.
func import_modding_mod_files_tables(table_names := [], table_base_paths := []) -> void:
	var mod_table_paths := {}
	if DirAccess.dir_exists_absolute(_modding_mod_files_dir):
		_add_table_paths_recursive(_modding_mod_files_dir, mod_table_paths)
	if !mod_table_paths:
		return # no mod tables!
	
	var modded_tables: Array[String] = []
	var modding_table_resources := {}
	var names := table_names.duplicate()
	for path: String in table_base_paths:
		var name := path.get_basename().get_file()
		names.append(name)
	for name: String in names:
		if !mod_table_paths.has(name):
			continue
		var path: String = mod_table_paths[name]
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file)
		var table_res := TableResource.new()
		table_res.import_file(file, path)
		modding_table_resources[name] = table_res
		modded_tables.append(name)
	if !modding_table_resources:
		return
	
	print("Applying user mod tables for: ", modded_tables)
	var table_postprocessor := IVTableData.table_postprocessor
	table_postprocessor.set_modding_tables(modding_table_resources)


func _add_table_paths_recursive(dir_path: String, dict: Dictionary) -> void:
	# 'dir_path' must exist.
	var dir := DirAccess.open(dir_path)
	dir.list_dir_begin()
	var file_or_dir_name := dir.get_next()
	while file_or_dir_name:
		var path := dir_path.path_join(file_or_dir_name)
		if dir.current_is_dir():
			_add_table_paths_recursive(path, dict)
		elif file_or_dir_name.get_extension() == "tsv":
			dict[file_or_dir_name.get_basename()] = path
		file_or_dir_name = dir.get_next()


func _get_original_table_path(name: String, original_table_paths: Array) -> String:
	for source_path: String in original_table_paths:
		if source_path.get_basename().get_file() == name:
			return source_path
	return ""


func _is_file_in_paths_array(file_name: String, paths: Array) -> bool:
	for path: String in paths:
		if path.get_file() == file_name:
			return true
	return false


func _remove_files_recursive(dir_path: String, extension: String) -> void:
	# Removes files in dir_path and dir_path subdirectories with specified extension.
	# Use extension == "" to remove all files. Also removes subdirectories if
	# they are empty after file removal. OK if dir_path doesn't exist.
	if !dir_path.begins_with("res://") and !dir_path.begins_with("user://"):
		return # make disaster a little less likely
	var dir := DirAccess.open(dir_path)
	if !dir:
		return
	dir.list_dir_begin()
	var file_or_dir_name := dir.get_next()
	while file_or_dir_name:
		if dir.current_is_dir():
			_remove_files_recursive(dir_path.path_join(file_or_dir_name), extension)
			dir.remove(file_or_dir_name) # only happens if empty
		elif !extension or file_or_dir_name.get_extension() == extension:
			FileAccess.set_read_only_attribute(dir_path.path_join(file_or_dir_name), false)
			dir.remove(file_or_dir_name)
		file_or_dir_name = dir.get_next()
