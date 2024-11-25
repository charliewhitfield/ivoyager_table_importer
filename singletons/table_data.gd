# table_data.gd
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
extends Node

## Singleton that provides all interface to data tables.
##
## This node is added as singleton 'IVTableData'.[br][br]
##
## Data dictionaries are populated only after calling [method postprocess_tables].
## Data can be accessed directly in dictionary/array structures or via methods.
## All table data is read-only![br][br]
##
## The methods API is useful for object construction and GUI. It has asserts to
## catch usage and type errors. For very optimized operation, a local reference
## to a field array is the fastest way to go.  
##
## All postprocessed table data is in dictionary [member tables] indexed by table
## name (e.g., 'planets', not 'planets.tsv').[br][br]
##
## The data structure for individual tables depends on table type:[br][br]
##
## * 'DB-style' tables are dictionaries of field arrays and can be indexed by
##   [field_name][row_int] where row_int can be obtained from
##   [member enumerations].[br][br]
## 
## * 'Enum x enum' tables are arrays of arrays and can be indexed by
##   [row_enum][col_enum]. Swap row & column if table has @TRANSPOSE directive.[br][br]
##
## See plugin
## [url=https://github.com/ivoyager/ivoyager_table_importer/blob/master/README.md]README[/url]
## for details.

## Default values for [missing_values].
const DEFAULT_MISSING_VALUES := {
	TYPE_BOOL : false,
	TYPE_STRING : "",
	TYPE_STRING_NAME : &"",
	TYPE_INT : -1,
	TYPE_FLOAT : NAN, # Watch out for failed '==' comparisons!
	TYPE_VECTOR3 : Vector3(-INF, -INF, -INF),
	TYPE_COLOR : Color(-INF, -INF, -INF, -INF),
	TYPE_ARRAY : [], # Arrays always have a data type! Don't change this one!
}

const DEFAULT_TABLE_CONSTANTS := {
	&"x" : true,
	&"true" : true,
	&"True" : true,
	&"TRUE" : true,
	&"false" : false,
	&"False" : false,
	&"FALSE" : false,
	&"nan" : NAN,
	&"NAN" : NAN,
	&"?" : INF,
	&"inf" : INF,
	&"INF" : INF,
	&"-?" : -INF,
	&"-inf" : -INF,
	&"-INF" : -INF,
}


## Contains all postprocessed table data. See class comments for structure.
var tables := {}
## Indexed by 1st-column entity names from [b]all[/b] 'db-style' tables, which
## are required to be globally unique ([method postprocess_tables] will assert
## if this is not the case). Values are row number integers from the individual tables.
var enumerations := {}
## Contains 'enum-like' enumerations for each table as a separate dictionary. This
## dictionary is indexed by table name [i]and[/i] by individual entity (i.e. row) names. You
## can use the latter to obtain the full table enumeration given any single table entity name.
var enumeration_dicts := {}
## See [member enumeration_dicts]. This is the same except the enumerations are inverted
## (array index is the enumeration value).
var enumeration_arrays := {}
## Number of rows for each 'db-style' table indexed by table name.
var table_n_rows := {}
## Indexed by table name for 'db-style' tables. This is the value specified as prefix
## for the 1st column entity names. E.g., in a planets.tsv table with entities
## PLANET_MERCURY, PLANET_VENUS, etc., it should be 'PLANET_'.
var entity_prefixes := {}
## Not populated by default. Set [code]enable_wiki = true[/code] in [method postprocess_tables]
## to populate. Indexed by table 1st-column entity names and provides a wiki 'key' if provided in
## table (e.g., 'en.wiki' column). This is used by
## [url=https://github.com/ivoyager/planetarium]Planetarium[/url] to link to Wikipedia.org
## pages, but it should be reconfigurable to link to an internal game wiki.
var wiki_lookup := {}
## Not populated by default. Set [code]enable_precisions = true[/code] in [method postprocess_tables]
## to populate. Has nested indexing structure exactly parallel with [member tables] except
## it only has FLOAT columns. Provides significant digits as determined from the table
## number text. This is useful only to science geeks making science projects like our
## [url=https://github.com/ivoyager/planetarium]Planetarium[/url] (for example).
var precisions := {}
## Defines how text in table files is interpreted if the cell or Default is
## not empty. Constants are used [i]without[/i] any other specified postprocessing,
## such as Prefix or Unit. E.g., if key:value MARS_PERIHELION:<float> exists we expect it to be
## already in internal units. The constant is used only if the type is correct for the column or
## container element, with STRING and STRING_NAME being mutually compatable. E.g.,
## a cell with "NAN" that is type STRING is just the text value: the float value
## would not be substituted. User can add, replace or disable values by supplying
## [param merge_table_constants] in [method postprocess_tables] (use null to disable
## an existing value).
var table_constants := DEFAULT_TABLE_CONSTANTS
## Defines how an empty table cell without Default is interpreted by the postprocessor
## by column type ([annotation @GlobalScope.Variant.Type]).
## Use [param replacement_missing_values] in [method postprocess_tables]
## to replace this dictionary. Note: The reason for strange values here such as
## Color(-INF,-INF,-INF,-INF), rather than Color.BLACK, is that API constructor methods
## like [method db_build_object] won't assign propeties that are 'missing' in the table.
## Hence, Color.BLACK won't be set on an object if that is defined as the missing color.[br]
## WARNING: TYPE_ARRAY must have value [].[br]
## WARNING: Replacement has not been tested!
var missing_values := DEFAULT_MISSING_VALUES
## This will be null after calling [method postprocess_tables]. It's accessible before
## postprocessing for [IVTableModding].
var table_postprocessor := IVTablePostprocessor.new()

var _is_missing_float_nan := true

## Call this function once to populate dictionaries with postprocessed table
## data. All containers are set to read-only. See comments in units.gd to
## change float conversion units. 
## Dictionary 'table_constants' can contain values of any type; it
## is merged with an existing dictionary.
## WARNING: Changing 'missing_values' should work for most types but has not been tested.
func postprocess_tables(table_file_paths: Array, project_enums := [], enable_wiki := false,
		enable_precisions := false, merge_table_constants := {}, replacement_missing_values := {}
		) -> void:
	
	if merge_table_constants:
		table_constants.merge(merge_table_constants, true)
	if replacement_missing_values:
		missing_values = replacement_missing_values
	var missing_float: float = missing_values[TYPE_FLOAT]
	_is_missing_float_nan = is_nan(missing_float)
	var table_file_paths_: Array[String] = Array(table_file_paths, TYPE_STRING, &"", null)
	var project_enums_: Array[Dictionary] = Array(project_enums, TYPE_DICTIONARY, &"", null)
	table_postprocessor.postprocess(table_file_paths_, project_enums_, tables, enumerations,
			enumeration_dicts, enumeration_arrays, table_n_rows, entity_prefixes, wiki_lookup,
			precisions, enable_wiki, enable_precisions, table_constants, missing_values)
	table_postprocessor = null
	
	var test: Array[float] = []
	print("testing ", test == [])


# For get functions below, table is "planets", "moons", etc. Most get functions
# accept either row (int) or entity (StringName), but not both!
#
# In general, functions will throw an error if 'table' or a specified 'entity'
# is missing or 'row' is out of range. However, a missing 'field' will not
# error and will return a 'null'-type value: "", &"", NAN, -1 or [].
# (This is needed for dictionary and object constructor methods.)

## Returns -1 if missing. All entities are globally unique.
func get_row(entity: StringName) -> int:
	return enumerations.get(entity, -1)


## Returns an enum-like dictionary of row numbers keyed by table name or the 
## name of any entity in the table.
## Works for DB_ENTITIES and ENUMERATION tables and 'project_enums'.
func get_enumeration_dict(table_or_entity: StringName) -> Dictionary:
	assert(enumeration_dicts.has(table_or_entity),
			"Specified table or entity '%s' does not exist or table does not have entity names"
			% table_or_entity)
	return enumeration_dicts[table_or_entity] # read-only


## Returns an array of entity names (i.e., an inversion of an enumeration dictionary)
## keyed by table name or the name of any entity in the table.
## Works for DB_ENTITIES and ENUMERATION tables.
## Also works for 'project_enums' IF it is simple sequential: 0, 1, 2,...
func get_enumeration_array(table_or_entity: StringName) -> Array[StringName]:
	assert(enumeration_dicts.has(table_or_entity),
			"Specified table or entity '%s' does not exist or table does not have entity names"
			% table_or_entity)
	return enumeration_arrays[table_or_entity] # read-only


## Works for DB_ENTITIES and ENUMERATION tables.
func has_entity_name(table: StringName, entity: StringName) -> bool:
	assert(enumeration_dicts.has(table),
			"Specified table '%s' does not exist or does not have entity names" % table)
	var enumeration_dict: Dictionary = enumeration_dicts[table]
	return enumeration_dict.has(entity)


## Works for DB_ENTITIES, DB_ANONYMOUS_ROWS and ENUMERATION tables.
func get_n_rows(table: StringName) -> int:
	assert(table_n_rows.has(table),
			"Specified table '%s' does not exist" % table)
	return table_n_rows[table]


## Works for DB_ENTITIES and ENUMERATION tables.
## Will return "" unless table has header 'Prefix/<entity_prefix>'.
func get_entity_prefix(table: StringName) -> String:
	assert(entity_prefixes.has(table),
			"Specified table '%s' does not exist" % table)
	return entity_prefixes[table]



# All below work only for DB_ENTITIES and DB_ANONYMOUS_ROWS.


## Returns &"" if table is DB_ANONYMOUS_ROWS or if row is out of bounds.
## Returns entity name for DB_ENTITIES tables only.
func get_db_entity_name(table: StringName, row: int) -> StringName:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	if !enumeration_arrays.has(table):
		return &""
	var enumeration_array: Array[StringName] = enumeration_arrays[table]
	if row < 0 or row >= enumeration_array.size():
		return &""
	return enumeration_array[row]


## Return array is content-typed by field and read-only.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_field_array(table: StringName, field: StringName) -> Array:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return []
	return table_dict[field] # read-only


## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_find(table: StringName, field: StringName, value: Variant) -> int:
	# Returns row number of value in field.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return -1
	var field_array: Array = table_dict[field]
	return field_array.find(value)


## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func count_db_matching(table: StringName, field: StringName, match_value: Variant) -> int:
	# Returns -1 if field not found.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return -1
	var column_array: Array = table_dict[field]
	return column_array.count(match_value)


## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_matching_rows(table: StringName, field: StringName, match_value: Variant) -> Array[int]:
	# May cause error if match_value type differs from field column.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
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


## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_true_rows(table: StringName, field: StringName) -> Array[int]:
	# Any value that evaluates true in an 'if' statement. Type is not enforced.
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return [] as Array[int]
	var column_array: Array = table_dict[field]
	var size := column_array.size()
	var result: Array[int] = []
	var row := 0
	while row < size:
		if column_array[row]:
			result.append(row)
		row += 1
	return result


## Returns true if the table has field and does not contain type-specific
## 'missing' value defined in [member missing_values].
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_has_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	var value: Variant = table_dict[field][row]
	var type := typeof(value)
	if type == TYPE_FLOAT and _is_missing_float_nan:
		var float_value: float = value
		if is_nan(float_value):
			return false
	return value != missing_values[type]


## Returns true if the table has field and does not contain float-specific
## 'missing' value defined in [member missing_values] (NAN by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_has_float_value(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return false
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	var float_value: float = table_dict[field][row]
	if _is_missing_float_nan and is_nan(float_value):
		return false
	return float_value != missing_values[TYPE_FLOAT]


## Use for STRING field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist ("" by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_string(table: StringName, field: StringName, row := -1, entity := &"") -> String:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_STRING]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for STRING_NAME field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (&"" by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_string_name(table: StringName, field: StringName, row := -1, entity := &""
		) -> StringName:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_STRING_NAME]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for BOOL field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (false by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_bool(table: StringName, field: StringName, row := -1, entity := &"") -> bool:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_BOOL]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for INT field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (-1 by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_int(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	# Use for field Type = INT; returns -1 if missing
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_INT]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for FLOAT field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (NAN by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_float(table: StringName, field: StringName, row := -1, entity := &"") -> float:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_FLOAT]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for VECTOR3 field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (Vector3(-INF,-INF,-INF) by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_vector3(table: StringName, field: StringName, row := -1, entity := &"") -> Vector3:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_VECTOR3]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for COLOR field. Returns 'missing' value defined in [member missing_values]
## if empty cell or field does not exist (Color(-INF,-INF,-INF,-INF) by default).
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_color(table: StringName, field: StringName, row := -1, entity := &"") -> Color:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return missing_values[TYPE_COLOR]
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Use for ARRAY[<content_type>] field. Returns an empty typed array if empty cell.
## Returns an empty untyped array if field does not exist.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_array(table: StringName, field: StringName, row := -1, entity := &"") -> Array:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var table_dict: Dictionary = tables[table]
	if !table_dict.has(field):
		return []
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return table_dict[field][row]


## Returns -1 if the field does not exist or is not type FLOAT.
## Asserts if [code]enable_precisions = false[/code] (default) in [method postprocess_tables].
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_float_precision(table: StringName, field: StringName, row := -1, entity := &"") -> int:
	
	assert(precisions.has(table),
			"No precisions for '%s'; did you set enable_precisions = true?" % table)
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	var precisions_dict: Dictionary = precisions[table]
	if !precisions_dict.has(field):
		return -1
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	return precisions_dict[field][row]


## Returns the lowest precision in a set of fields. All fields must exist and be type FLOAT.
## Asserts if [code]enable_precisions = false[/code] (default) in [method postprocess_tables].
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_least_float_precision(table: StringName, fields: Array[StringName], row := -1,
		entity := &"") -> int:
	assert(precisions.has(table),
			"No precisions for '%s'; did you set enable_precisions = true?" % table)
	assert((row == -1) != (entity == &""), "Requires either row or entity (not both)")
	if entity:
		assert(enumerations.has(entity), "Unknown table enumeration '%s'" % entity)
		row = enumerations[entity]
	var min_precision := 9999
	for field in fields:
		var precission: int = precisions[table][field][row]
		if min_precision > precission:
			min_precision = precission
	return min_precision


## Returns an array with an integer value for each specified field. Missing and
## non-FLOAT fields are allowed and will have precision -1.
## Asserts if [code]enable_precisions = false[/code] (default) in [method postprocess_tables].
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_float_precisions(fields: Array[StringName], table: StringName, row: int) -> Array[int]:
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


## Returns an array with a value for each specified field. All fields must exist.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func get_db_row_data_array(fields: Array[StringName], table: StringName, row: int) -> Array:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
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


## Sets a dictionary key:value pair for every field in table from
## [param fields] that has a non-'missing' value.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_build_dictionary(dict: Dictionary, fields: Array[StringName], table: StringName, row: int
		) -> void:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if db_has_value(table, field, row):
			dict[field] = table_dict[field][row]
		i += 1


## Sets value for each existing dictionary key that exactly matches a column
## field in table. Missing value in table without default will not be set.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_build_dictionary_from_keys(dict: Dictionary, table: StringName, row: int) -> void:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	assert(dict, "Expected a dict with keys")
	var table_dict: Dictionary = tables[table]
	for field: StringName in dict:
		if db_has_value(table, field, row):
			dict[field] = table_dict[field][row]


## Sets object property for each field that exactly matches a field in table.
## Missing value in table without default will not be set.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_build_object(object: Object, fields: Array[StringName], table: StringName, row: int) -> void:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	var n_fields := fields.size()
	var i := 0
	while i < n_fields:
		var field: StringName = fields[i]
		if db_has_value(table, field, row):
			object.set(field, table_dict[field][row])
		i += 1


## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
## Sets object property for each field that exactly matches a field in table.
## Missing value in table without default will not be set. 
func db_build_object_all_fields(object: Object, table: StringName, row: int) -> void:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	var table_dict: Dictionary = tables[table]
	for field: StringName in tables[table]:
		if db_has_value(table, field, row):
			object.set(field, table_dict[field][row])


## Sets flag if table value evaluates as true in [method get_db_bool]. Does not unset.
## Works for DB_ENTITIES and DB_ANONYMOUS_ROWS tables.
func db_get_flags(flag_fields: Dictionary, table: StringName, row: int, flags := 0) -> int:
	assert(tables.has(table), "Specified table '%s' does not exist" % table)
	assert(typeof(tables[table]) == TYPE_DICTIONARY, "Specified table must be 'DB' format")
	for flag: int in flag_fields:
		var field: StringName = flag_fields[flag]
		if get_db_bool(table, field, row):
			flags |= flag
	return flags
