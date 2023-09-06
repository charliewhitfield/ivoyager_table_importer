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
extends Node

# This node is loaded as singleton 'IVTableData' by table_plugin.gd.
# All user interface is here!

const TablePostprocessor := preload("table_postprocessor.gd")
const TableUtils := preload("table_utils.gd")

# Data dictionaries are populated only after postprocess_tables() is called.
# You can access data directly in these dictionaries or use API below.
#
# For DB format data, index as tables[table_name][field_name][row_int],
# where row_int = enumerations[entity_name].
# For these tables it's also possible to get the number of rows and the
# table-specified row entity prefix (e.g., "PLANETS_") using
# tables["n_" + table_name] and tables["prefix_" + table_name].
# 
# For enum x enum format, index as tables[table_name][row_enum][col_enum].

var tables := {} # postprocessed data
var enumerations := {} # indexed by ALL entity names (which are globally unique)
var enumeration_dicts := {} # use table name or ANY entity name to get entity enumeration dict
var wiki_lookup := {} # populated if enable_wiki
var precisions := {} # populated if enable_precisions (indexed as tables for FLOAT fields)


func postprocess_tables(table_file_paths: Array, project_enums := [], unit_multipliers := {},
		unit_lambdas := {}, enable_wiki := false, enable_precisions := false) -> void:
	# Call this function to populate dictionaries with postprocessed data.
	# See table_unit_defaults.gd for default unit conversion to SI base units.
	
	# Cast arrays here so user isn't forced to input typed arrays.
	var table_file_paths_: Array[String] = Array(table_file_paths, TYPE_STRING, &"", null)
	var project_enums_: Array[Dictionary] = Array(project_enums, TYPE_DICTIONARY, &"", null)
	
	# Set TableUtils conversion dictionaries if supplied here.
	if unit_multipliers:
		assert(!TableUtils.unit_multipliers or TableUtils.unit_multipliers == unit_multipliers,
				"A different 'unit_multipliers' was already set in TableUtils")
		TableUtils.unit_multipliers = unit_multipliers
	if unit_lambdas:
		assert(!TableUtils.unit_lambdas or TableUtils.unit_lambdas == unit_lambdas,
				"A different 'unit_lambdas' was already set in TableUtils")
		TableUtils.unit_lambdas = unit_lambdas
	
	# Verify conversion dictionaries set, or set to defaults.
	if !TableUtils.unit_multipliers or !TableUtils.unit_lambdas:
		# table_unit_defaults.gd will unload itself after this; we won't need it anymore
		var UnitDefaults := preload("table_unit_defaults.gd")
		if !TableUtils.unit_multipliers:
			TableUtils.unit_multipliers = UnitDefaults.unit_multipliers
		if !TableUtils.unit_lambdas:
			TableUtils.unit_lambdas = UnitDefaults.unit_lambdas

	# Postprocess after clearing data (maybe user calls again for some reason?)
	tables.clear()
	enumerations.clear()
	enumeration_dicts.clear()
	wiki_lookup.clear()
	precisions.clear()
	var table_postprocessor := TablePostprocessor.new()
	table_postprocessor.postprocess(table_file_paths_, project_enums_, tables,
			enumerations, enumeration_dicts, wiki_lookup, precisions,
			enable_wiki, enable_precisions)


# For get functions, table is "planets", "moons", etc. Most get functions
# accept either row (int) or entity (StringName), but not both!
#
# In general, functions will throw an error if 'table' or a specified 'entity'
# is missing, or 'row' is out of range. However, missing 'field' will not
# error and function will return type-null value "", &"", NAN, -1 or []
# (this is needed for dictionary and object constructor methods).

func get_row(entity: StringName) -> int:
	# Returns -1 if missing. All entity's are globally unique.
	return enumerations.get(entity, -1)


func get_entity_enumeration(table: StringName) -> Dictionary:
	assert(enumeration_dicts.has(table), "Specified table '%s' does not exist" % table)
	# Returns an enum-like dict of row numbers keyed by entity names.
	# Works for DB_ENTITIES and ENUMERATION tables.
	return enumeration_dicts[table]


func has_entity_name(table: StringName, entity: StringName) -> bool:
	# Works for DB_ENTITIES and ENUMERATION tables.
	assert(enumeration_dicts.has(table), "Specified table '%s' does not exist" % table)
	var enumeration: Dictionary = enumeration_dicts[table]
	return enumeration.has(entity)


# All below are DB_ENTITIES table only (possibly modified by DB_ENTITIES_MOD).

func get_db_n_rows(table: StringName) -> int:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	return tables["n_" + table]


func get_db_entity_prefix(table: StringName) -> String:
	# E.g., 'PLANET_' in planets.tsv.
	# Prefix must be specified for the table's 'name' column.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	return tables["prefix_" + table]


func get_db_entity_name(table: StringName, row: int) -> StringName:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(&"name"):
		return &""
	var name_array: Array[StringName] = table_dict[&"name"]
	if row < 0 or row >= name_array.size():
		return &""
	return name_array[row]


func get_db_field_array(table: StringName, field: StringName) -> Array:
	# Duplicated for safety. User can get internal array from dictionary.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return []
	return table_dict[field].duplicate()


func count_db_matching(table: StringName, field: StringName, match_value: Variant) -> int:
	# Returns -1 if field not found.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return -1
	var column_array: Array = table_dict[field]
	return column_array.count(match_value)


func get_db_matching_rows(table: StringName, field: StringName, match_value: Variant) -> Array[int]:
	# May cause error if match_value type differs from field column.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return [] as Array[int]
	var column_array: Array = table_dict[field]
	var size := column_array.size()
	var result: Array[int] = []
	var row := 0
	while row < size:
		if column_array[row] == match_value:
			result.append(row)
		row += 1
	return result


func get_db_true_rows(table: StringName, field: StringName) -> Array[int]:
	# Any value that evaluates true in an 'if' statement. Type is not enforced.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return [] as Array[int]
	var column_array: Array = table_dict[field]
	var size := column_array.size()
	var result := []
	var row := 0
	while row < size:
		if column_array[row]:
			result.append(row)
		row += 1
	return result


func db_has_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	# Returns true if table has field and does not contain type-specific
	# 'null' value: "", &"", NAN, -1 or [].
	# Always true for Type BOOL.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	var value: Variant = table_dict[field][row]
	var type := typeof(value)
	if type == TYPE_FLOAT:
		return !is_nan(value)
	if type == TYPE_INT:
		return value != -1
	if type == TYPE_STRING:
		return value != ""
	if type == TYPE_STRING_NAME:
		return value != &""
	if type == TYPE_ARRAY:
		return !value.is_empty()
	return true # BOOL


func db_has_float_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	# Returns true if table has field and float value is not NAN.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	return !is_nan(table_dict[field][row])


func get_db_string(table: StringName, field: StringName, row := -1, entity := &"") -> String:
	# Use for field Type = STRING; returns "" if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return ""
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_string_name(table: StringName, field: StringName, row := -1, entity := &""
		) -> StringName:
	# Use for field Type = STRING_NAME; returns &"" if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return &""
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_bool(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	# Use for field Type = BOOL; returns false if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_int(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	# Use for field Type = INT; returns -1 if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return -1
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_float(table: StringName, field: StringName, row := -1, entity := &"") -> float:
	# Use for field Type = FLOAT; returns NAN if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return NAN
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_array(table: StringName, field: StringName, row := -1, entity := &"") -> Array:
	# Use for field Type = ARRAY[xxxx]; returns [] if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return []
	if entity:
		row = enumerations[entity]
	return table_dict[field][row]


func get_db_float_precision(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	# field must be type FLOAT
	assert(precisions.has(table),
			"No precisions for '%s'; did you set enable_precisions = true?" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	var precisions_dict: Dictionary = precisions[table]
	if !precisions_dict.has(field):
		return -1
	if entity:
		row = enumerations[entity]
	return precisions_dict[field][row]


func get_db_least_float_precision(table: StringName, fields: Array[StringName], row := -1,
		entity := &"") -> int:
	# All fields must be type FLOAT
	assert(precisions.has(table),
			"No precisions for '%s'; did you set enable_precisions = true?" % table)
	assert((row == -1) != (entity == ""), "Requires either row or entity (not both)")
	if entity:
		row = enumerations[entity]
	var min_precision := 9999
	for field in fields:
		var precission: int = precisions[table][field][row]
		if min_precision > precission:
			min_precision = precission
	return min_precision


func get_db_float_precisions(fields: Array[StringName], table: StringName, row: int) -> Array[int]:
	# Missing or non-FLOAT values will have precision -1.
	assert(precisions.has(table),
			"No precisions for '%s'; did you set enable_precisions = true?" % table)
	var precisions_dict: Dictionary = precisions[table]
	var n_fields := fields.size()
	var result: Array[int] = []
	result.resize(n_fields)
	result.fill(-1)
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if precisions_dict.has(field):
			result[i] = precisions_dict[field][row]
		i += 1
	return result


func get_db_row_data_array(fields: Array[StringName], table: StringName, row: int) -> Array:
	# Returns an array with value for each field; all fields must exist.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	var n_fields := fields.size()
	var data := []
	data.resize(n_fields)
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		data[i] = table_dict[field][row]
		i += 1
	return data


func db_build_dictionary(dict: Dictionary, fields: Array[StringName], table: StringName, row: int
		) -> void:
	# Sets dict value for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if db_has_value(table, field, row):
			dict[field] = table_dict[field][row]
		i += 1


func db_build_dictionary_from_keys(dict: Dictionary, table: StringName, row: int) -> void:
	# Sets dict value for each existing dict key that exactly matches a column
	# field in table. Missing value in table without default will not be set.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	for field in dict:
		if db_has_value(table, field, row):
			dict[field] = table_dict[field][row]


func db_build_object(object: Object, fields: Array[StringName], table: StringName, row: int) -> void:
	# Sets object property for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if db_has_value(table, field, row):
			object.set(field, table_dict[field][row])
		i += 1


func db_build_object_all_fields(object: Object, table: StringName, row: int) -> void:
	# Sets object property for each field that exactly matches a field in table.
	# Missing value in table without default will not be set.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	var table_dict: Dictionary = tables[table]
	for field in tables[table]:
		if db_has_value(table, field, row):
			object.set(field, table_dict[field][row])


func db_get_flags(flag_fields: Dictionary, table: StringName, row: int, flags := 0) -> int:
	# Sets flag if table value exists and would evaluate true in get_db_bool(),
	# i.e., is true or x. Does not unset.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	for flag in flag_fields:
		var field: StringName = flag_fields[flag]
		if get_db_bool(table, field, row):
			flags |= flag
	return flags

