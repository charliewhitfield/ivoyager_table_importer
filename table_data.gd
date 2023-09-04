# table_data.gd
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
extends Node

# This node is loaded as singleton 'IVTableData' by table_plugin.gd.
#
# All user interface is here!

const VERSION := "0.0.1-dev"
const VERSION_YMD := 20230903

const TablePostprocessor := preload("table_postprocessor.gd")
const TableUtils := preload("table_utils.gd")

# Data dictionaries are populated only after postprocess_tables() is called.
# You can access data directly in these dictionaries or use API below.
#
# For DB format tables, index as tables[table_name][field_name][row_int],
# where row_int = enumerations[entity_name]
#
# For enum x enum format, index as tables[table_name][row_enum][col_enum].


var tables := {} # postprocessed data
var enumerations := {} # indexed by ALL entity names (which are globally unique)
var enumeration_dicts := {} # use table name or ANY entity name to get entity enumeration dict
var wiki_lookup := {} # populated if enable_wiki
var precisions := {} # populated if enable_precisions (indexed as tables for FLOAT fields)


func _enter_tree():
	
	var version_str := VERSION
	if version_str.ends_with("-dev"):
		version_str += " " + str(VERSION_YMD)
	print("IVoyager Table Importer v%s - https://ivoyager.dev" % version_str)


func postprocess_tables(table_file_paths: Array, project_enums := [], unit_multipliers := {},
		unit_lambdas := {}, enable_wiki := false, enable_precisions := false) -> void:
	# Call this function to populate dictionaries with postprocessed data.
	# See table_unit_defaults.gd for default unit conversion to SI base units.
	
	# Cast arrays here so user isn't forced to input typed arrays.
	var table_file_paths_: Array[String] = Array(table_file_paths, TYPE_STRING, &"", null)
	var project_enums_: Array[Dictionary] = Array(project_enums, TYPE_DICTIONARY, &"", null)
	
	# Set TableUtils conversion dictionaries here, or verify set, or set to defaults.
	if unit_multipliers:
		assert(!TableUtils.unit_multipliers or TableUtils.unit_multipliers == unit_multipliers,
				"A different 'unit_multipliers' was already set in TableUtils")
		TableUtils.unit_multipliers = unit_multipliers
	if unit_lambdas:
		assert(!TableUtils.unit_lambdas or TableUtils.unit_lambdas == unit_lambdas,
				"A different 'unit_lambdas' was already set in TableUtils")
		TableUtils.unit_lambdas = unit_lambdas
	if !TableUtils.unit_multipliers or !TableUtils.unit_lambdas:
		# TableUnitDefaults will unload itself after this; we won't need it anymore
		var UnitDefaults := preload("table_unit_defaults.gd")
		if !TableUtils.unit_multipliers:
			TableUtils.unit_multipliers = UnitDefaults.unit_multipliers
		if !TableUtils.unit_lambdas:
			TableUtils.unit_lambdas = UnitDefaults.unit_lambdas
	
	var table_postprocessor := TablePostprocessor.new()
	table_postprocessor.postprocess(table_file_paths_, project_enums_, tables,
			enumerations, enumeration_dicts, wiki_lookup, precisions,
			enable_wiki, enable_precisions)


# For get functions, table is "planets", "moons", etc. Most get functions
# accept either row (int) or entity (StringName), but not both!
#
# Methods are mostly safe for nonexistent tables, missing fields, etc.,
# returning null-equivalent results (e.g., -1 for int) rather than causing an
# error. (Not all have been made safe yet.)


func get_n_rows(table: StringName) -> int:
	var key := StringName("n_" + table)
	return tables.get(key, -1)


func get_entity_prefix(table: StringName) -> String:
	# E.g., 'PLANET_' in planets.tsv.
	# Prefix must be specified for the table's 'name' column.
	var key := StringName("prefix_" + table)
	return tables.get(key, "")


func get_row_name(table: StringName, row: int) -> StringName:
	if !tables.has(table):
		return &""
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(&"name"):
		return &""
	var name_array: Array[StringName] = table_dict[&"name"]
	if row < 0 or row >= name_array.size():
		return &""
	return name_array[row]


func get_row(entity: StringName) -> int:
	# Returns -1 if missing. All entity's are globally unique.
	return enumerations.get(entity, -1)


func get_names_enumeration(table: StringName) -> Dictionary:
	# Returns an enum-like dict of row numbers keyed by row names.
	return enumeration_dicts.get(table, {})


func get_column_array(table: StringName, field: StringName) -> Array:
	# Returns internal array reference - DON'T MODIFY!
	return tables[table][field]


func get_n_matching(table: StringName, field: StringName, match_value) -> int:
	# field must exist in specified table
	# match_value type must mach column type
	var column_array: Array = tables[table][field]
	return column_array.count(match_value)


func get_matching_rows(table: StringName, field: StringName, match_value) -> Array:
	# field must exist in specified table
	# match_value type must mach column type
	var column_array: Array = tables[table][field]
	var size := column_array.size()
	var result := []
	var row := 0
	while row < size:
		if column_array[row] == match_value:
			result.append(row)
		row += 1
	return result


func get_true_rows(table: StringName, field: StringName) -> Array:
	# field must exist in specified table
	var column_array: Array = tables[table][field]
	var size := column_array.size()
	var result := []
	var row := 0
	while row < size:
		if column_array[row]:
			result.append(row)
		row += 1
	return result


func has_row_name(table: StringName, entity: StringName) -> bool:
	if !enumerations.has(entity):
		return false
	var table_dict: Dictionary = tables[table]
	if !table_dict.has("name"):
		return false
	var name_column: Array[StringName] = table_dict.name
	return name_column.has(entity)


func has_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	# Evaluates true if table has field and does not contain type-specific
	# 'null' value: i.e., "", NAN or -1 for STRING, FLOAT or INT, respectively.
	# Always true for Type BOOL.
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	var value = table_dict[field][row]
	var type := typeof(value)
	if type == TYPE_FLOAT:
		return !is_nan(value)
	if type == TYPE_INT:
		return value != -1
	if type == TYPE_STRING:
		return value != ""
	return true # BOOL


func has_float_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	return !is_nan(table_dict[field][row])


func get_string(table: StringName, field: StringName, row := -1, entity := &"") -> String:
	# Use for table Type 'STRING'; returns "" if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return ""
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_string_name(table: StringName, field: StringName, row := -1, entity := &"") -> StringName:
	# Use for table Type 'STRING_NAME'; returns &"" if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return &""
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_bool(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	# Use for table Type 'BOOL'; returns false if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_int(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	# Use for table Type 'INT'; returns -1 if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return -1
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_float(table: StringName, field: StringName, row := -1, entity := &"") -> float:
	# Use for table Type 'FLOAT'; returns NAN if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return NAN
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_array(table: StringName, field: StringName, row := -1, entity := &""): # returns typed array
	# Use for table Type 'ARRAY:xxxx'; returns [] if missing
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return []
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_float_precision(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	# field must be type FLOAT
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_prec_dict: Dictionary = tables[table]
	if !table_prec_dict.has(field):
		return -1
	if entity:
		row = enumerations[entity]
	return table_prec_dict[field][row]


func get_least_float_precision(table: StringName, fields: Array[StringName], row := -1,
		entity := &"") -> int:
	# All fields must be type FLOAT
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	if entity:
		row = enumerations[entity]
	var min_precision := 9999
	for field in fields:
		var precission: int = precisions[table][field][row]
		if min_precision > precission:
			min_precision = precission
	return min_precision


func get_float_precisions(fields: Array[StringName], table: StringName, row: int) -> Array:
	# Missing or non-FLOAT values will have precision -1.
	var this_table_precisions: Dictionary = precisions[table]
	var n_fields := fields.size()
	var result := []
	result.resize(n_fields)
	result.fill(-1)
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if this_table_precisions.has(field):
			result[i] = this_table_precisions[field][row]
		i += 1
	return result


func get_row_data_array(fields: Array[StringName], table: StringName, row: int) -> Array:
	# Returns an array with value for each field; all fields must exist.
	var n_fields := fields.size()
	var data := []
	data.resize(n_fields)
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		data[i] = tables[table][field][row]
		i += 1
	return data


func build_dictionary(dict: Dictionary, fields: Array[StringName], table: StringName, row: int
		) -> void:
	# Sets dict value for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if has_value(table, field, row):
			dict[field] = tables[table][field][row]
		i += 1


func build_dictionary_from_keys(dict: Dictionary, table: StringName, row: int) -> void:
	# Sets dict value for each existing dict key that exactly matches a column
	# field in table. Missing value in table without default will not be set.
	for field in dict:
		if has_value(table, field, row):
			dict[field] = tables[table][field][row]


func build_object(object: Object, fields: Array[StringName], table: StringName, row: int) -> void:
	# Sets object property for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if has_value(table, field, row):
			object.set(field, tables[table][field][row])
		i += 1


func build_object_all_fields(object: Object, table: StringName, row: int) -> void:
	# Sets object property for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	for field in tables[table]:
		if has_value(table, field, row):
			object.set(field, tables[table][field][row])


func get_flags(flag_fields: Dictionary, table: StringName, row: int, flags := 0) -> int:
	# Sets flag if table value exists and would evaluate true in get_bool(),
	# i.e., is true or x. Does not unset.
	for flag in flag_fields:
		var field: StringName = flag_fields[flag]
		if get_bool(table, field, row):
			flags |= flag
	return flags


