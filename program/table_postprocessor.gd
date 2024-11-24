# table_postprocessor.gd
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
extends RefCounted


enum TableDirectives { # copy from table_resource.gd
	# table formats
	DB_ENTITIES,
	DB_ENTITIES_MOD,
	DB_ANONYMOUS_ROWS,
	ENUMERATION,
	WIKI_LOOKUP,
	ENUM_X_ENUM,
	N_FORMATS,
	# specific directives
	MODIFIES,
	DATA_TYPE,
	DATA_DEFAULT,
	DATA_UNIT,
	TRANSPOSE,
	# any file
	DONT_PARSE, # do nothing (for debugging or under-construction table)
}


const TableResource := preload("../editor_plugin/table_resource.gd")

# TODO: Proper localization. I'm not sure if we're supposed to use get_locale()
# from OS or TranslationServer, or how to do fallbacks for missing translations.
var localized_wiki := &"en.wiki"

var _tables: Dictionary # postprocessed data indexed [table_name][field_name][row_int]
var _enumerations: Dictionary # indexed by ALL entity names (which are globally unique)
var _enumeration_dicts: Dictionary # indexed by table name & all entity names
var _enumeration_arrays: Dictionary # indexed as above
var _table_n_rows: Dictionary # indexed by table name
var _entity_prefixes: Dictionary # indexed by table name
var _wiki_lookup: Dictionary # populated if enable_wiki
var _precisions: Dictionary # populated if enable_precisions (indexed as tables for FLOAT fields)
var _enable_wiki: bool
var _enable_precisions: bool

var _float_constants := { # user supplied is merged w/ overwrite = false
	&"" : NAN,
	&"NAN" : NAN,
	&"nan" : NAN,
	&"?" : INF,
	&"INF" : INF,
	&"inf" : INF,
	&"-?" : -INF,
	&"-INF" : -INF,
	&"-inf" : -INF,
}

var _table_defaults := {} # only tables that might be modified

var _modding_table_resources: Dictionary

var _start_msec: int
var _count: int



func set_modding_tables(modding_table_resources: Dictionary) -> void:
	# Called by IVTableModding. If used, must be called before postprocess().
	_modding_table_resources = modding_table_resources


func postprocess(table_file_paths: Array[String], project_enums: Array[Dictionary],
		tables: Dictionary, enumerations: Dictionary, enumeration_dicts: Dictionary,
		enumeration_arrays: Dictionary, table_n_rows: Dictionary, entity_prefixes: Dictionary,
		wiki_lookup: Dictionary, precisions: Dictionary, enable_wiki: bool, enable_precisions: bool,
		float_constants: Dictionary) -> void:
	# Called by IVTableData.
	
	_start_msec = Time.get_ticks_msec()
	_count = 0
	
	_tables = tables
	_enumerations = enumerations
	_enumeration_dicts = enumeration_dicts
	_enumeration_arrays = enumeration_arrays
	_table_n_rows = table_n_rows
	_entity_prefixes = entity_prefixes
	_wiki_lookup = wiki_lookup
	_precisions = precisions
	_enable_wiki = enable_wiki
	_enable_precisions = enable_precisions
	_float_constants.merge(float_constants)
	
	var table_resources: Array[TableResource] = []
	for path in table_file_paths:
		var name := path.get_basename().get_file()
		var table_res: TableResource
		if _modding_table_resources and _modding_table_resources.has(name):
			table_res = _modding_table_resources[name]
		else:
			table_res = load(path)
		table_resources.append(table_res)
	
	# move mod tables to end (this is the only case where order matters)
	var i := 0
	var stop := table_resources.size()
	while i < stop:
		var table_res := table_resources[i]
		if table_res.table_format == TableDirectives.DB_ENTITIES_MOD:
			table_resources.remove_at(i)
			table_resources.append(table_res)
			stop -= 1
		else:
			i += 1
	
	# add project enums
	for project_enum in project_enums:
		var is_simple_sequential := true # test this
		i = 0
		for entity_name: StringName in project_enum:
			if project_enum[entity_name] != i:
				is_simple_sequential = false
				break
			i += 1
		var size := project_enum.size()
		var enum_array: Array[StringName] = []
		if is_simple_sequential:
			enum_array.resize(size)
		for entity_name: StringName in project_enum:
			assert(!enumerations.has(entity_name), "Table enumerations must be globally unique!")
			var enumeration: int = project_enum[entity_name]
			enumerations[entity_name] = enumeration
			enumeration_dicts[entity_name] = project_enum # needed for ENUM_X_ENUM
			if is_simple_sequential:
				enum_array[enumeration] = entity_name
				enumeration_arrays[entity_name] = enum_array
	
	# add/modify table enumerations
	for table_res in table_resources:
		
		match table_res.table_format:
			TableDirectives.DB_ENTITIES, TableDirectives.ENUMERATION:
				_add_table_enumeration(table_res)
			TableDirectives.DB_ENTITIES_MOD:
				_modify_table_enumeration(table_res)
	
	# postprocess data by format
	for table_res in table_resources:
		
		match table_res.table_format:
			TableDirectives.DB_ENTITIES:
				_postprocess_db_table(table_res, true)
			TableDirectives.DB_ANONYMOUS_ROWS:
				_postprocess_db_table(table_res, false)
			TableDirectives.ENUMERATION:
				_postprocess_enumeration(table_res)
			TableDirectives.DB_ENTITIES_MOD:
				_postprocess_db_entities_mod(table_res)
			TableDirectives.WIKI_LOOKUP:
				_postprocess_wiki_lookup(table_res)
			TableDirectives.ENUM_X_ENUM:
				_postprocess_enum_x_enum(table_res)
	
	# make all containers read-only
	tables.make_read_only()
	enumerations.make_read_only()
	enumeration_dicts.make_read_only()
	enumeration_arrays.make_read_only()
	table_n_rows.make_read_only()
	entity_prefixes.make_read_only()
	wiki_lookup.make_read_only()
	precisions.make_read_only()
	
	for table_name: StringName in tables:
		if typeof(tables[table_name]) == TYPE_DICTIONARY:
			var dict_of_field_arrays: Dictionary = tables[table_name]
			dict_of_field_arrays.make_read_only()
			for field: StringName in dict_of_field_arrays:
				var field_array: Array = dict_of_field_arrays[field]
				field_array.make_read_only()
				if field_array.get_typed_builtin() == TYPE_ARRAY:
					for array: Array in field_array:
						array.make_read_only()
		else:
			var array_of_arrays: Array[Array] = tables[table_name]
			array_of_arrays.make_read_only()
			for array in array_of_arrays:
				array.make_read_only()
	
	for key: StringName in enumeration_dicts:
		var enumeration_dict: Dictionary = enumeration_dicts[key]
		enumeration_dict.make_read_only()
	
	for key: StringName in enumeration_arrays:
		var enumeration_array: Array[StringName] = enumeration_arrays[key]
		enumeration_array.make_read_only()
	
	for table_name: StringName in precisions:
		var dict_of_field_arrays: Dictionary = precisions[table_name]
		dict_of_field_arrays.make_read_only()
		for field: StringName in dict_of_field_arrays:
			var field_array: Array[int] = dict_of_field_arrays[field]
			field_array.make_read_only()
	
	var msec := Time.get_ticks_msec() - _start_msec
	print("Processed %s table items in %s msec" % [_count, msec])


func c_unescape_patch(text: String) -> String:
	# Patch method to read '\u' escape; see open Godot issue #38716.
	# This can read 'small' unicodes up to '\uFFFF'.
	# Godot doesn't seem to support larger '\Uxxxxxxxx' unicodes as of 4.1.1.
	var u_esc := text.find("\\u")
	while u_esc != -1:
		var esc_str := text.substr(u_esc, 6)
		var hex_str := esc_str.replace("\\u", "0x")
		var unicode := hex_str.hex_to_int()
		var unicode_chr := char(unicode)
		text = text.replace(esc_str, unicode_chr)
		u_esc = text.find("\\u")
	return text


func _add_table_enumeration(table_res: TableResource) -> void:
	var table_name := table_res.table_name
	var enumeration_dict := {}
	assert(!_enumeration_dicts.has(table_name), "Duplicate table name")
	_enumeration_dicts[table_name] = enumeration_dict
	var row_names := table_res.row_names
	var enumeration_array: Array[StringName] = row_names.duplicate()
	_enumeration_arrays[table_name] = enumeration_array
	for row in row_names.size():
		var entity_name := row_names[row]
		enumeration_dict[entity_name] = row
		assert(!_enumerations.has(entity_name), "Table enumerations must be globally unique!")
		_enumerations[entity_name] = row
		assert(!_enumeration_dicts.has(entity_name), "??? entity_name == table_name ???")
		_enumeration_dicts[entity_name] = enumeration_dict
		_enumeration_arrays[entity_name] = enumeration_array


func _modify_table_enumeration(table_res: TableResource) -> void:
	var modifies_name := table_res.modifies_table_name
	assert(_enumeration_dicts.has(modifies_name), "No enumeration for " + modifies_name)
	var enumeration_dict: Dictionary = _enumeration_dicts[modifies_name]
	var enumeration_array: Array[StringName] = _enumeration_arrays[modifies_name]
	var row_names := table_res.row_names
	for row in row_names.size():
		var entity_name := row_names[row]
		if enumeration_dict.has(entity_name):
			continue
		var new_row := enumeration_array.size()
		enumeration_dict[entity_name] = new_row
		enumeration_array.resize(new_row + 1)
		enumeration_array[new_row] = entity_name
		assert(!_enumerations.has(entity_name), "Mod entity exists in another table")
		_enumerations[entity_name] = new_row
		assert(!_enumeration_dicts.has(entity_name), "??? entity_name == table_name ???")
		_enumeration_dicts[entity_name] = enumeration_dict
		_enumeration_arrays[entity_name] = enumeration_array


func _postprocess_enumeration(table_res: TableResource) -> void:
	var table_name := table_res.table_name
	_table_n_rows[table_name] = table_res.n_rows
	_entity_prefixes[table_name] = table_res.entity_prefix
	_count += _table_n_rows[table_name]


func _postprocess_db_table(table_res: TableResource, has_entity_names: bool) -> void:
	var table_dict := {}
	var table_name := table_res.table_name
	var column_names := table_res.column_names
	var row_names := table_res.row_names
	var dict_of_field_arrays := table_res.dict_of_field_arrays
	var prefixes := table_res.db_prefixes
	var types := table_res.db_types
	var import_defaults := table_res.db_import_defaults
	var units := table_res.db_units
	var n_rows := table_res.n_rows
	var unindexing := _get_unindexing(table_res.indexing)
	
	var defaults := {} # need for table mods
	
	if has_entity_names:
		table_dict[&"name"] = _enumeration_arrays[table_name]
	if _enable_precisions:
		_precisions[table_name] = {}
	
	for field in column_names:
		var import_field: Array = dict_of_field_arrays[field]
		assert(n_rows == import_field.size())
		var prefix: String = prefixes.get(field, "")
		var type: int = types[field]
		var unit: StringName = units.get(field, &"")
		var field_type := type if type < TYPE_MAX else TYPE_ARRAY
		var new_field := Array([], field_type, &"", null)
		new_field.resize(n_rows)
		for row in n_rows:
			var import_idx: int = import_field[row]
			var import_str: String = unindexing[import_idx]
			new_field[row] = _get_postprocess_value(import_str, prefix, type, unit)
			_count += 1
		table_dict[field] = new_field
		# keep table default (temporarly) in case this table is modified
		if has_entity_names:
			var import_default_idx: int = import_defaults.get(field, 0)
			var import_default_str: String = unindexing[import_default_idx]
			var default: Variant = _get_postprocess_value(import_default_str, prefix, type, unit)
			defaults[field] = default
		# wiki
		if field == localized_wiki:
			assert(has_entity_names, "Wiki lookup column requires row names")
			if _enable_wiki:
				for row in n_rows:
					var wiki_title: String = new_field[row]
					if wiki_title:
						var row_name := row_names[row]
						_wiki_lookup[row_name] = wiki_title
		# precisions
		if _enable_precisions and type == TYPE_FLOAT:
			var precisions_field := Array([], TYPE_INT, &"", null)
			precisions_field.resize(n_rows)
			for row in n_rows:
				
				
				var index: int = import_field[row]
				var float_string: String = unindexing[index]
				
				
				#var float_string: String = import_field[row]
				precisions_field[row] = _get_float_str_precision(float_string)
			_precisions[table_name][field] = precisions_field
	
	_tables[table_name] = table_dict
	_table_n_rows[table_name] = n_rows
	
	if has_entity_names:
		_entity_prefixes[table_name] = table_res.entity_prefix
		_table_defaults[table_name] = defaults # possibly needed for DB_ENTITIES_MOD


func _postprocess_db_entities_mod(table_res: TableResource) -> void:
	# We don't modify the table resource. We do modify postprocessed table.
	# TODO: Should work if >1 mod table for existing table, but need to test.
	var modifies_table_name := table_res.modifies_table_name
	assert(_tables.has(modifies_table_name), "Can't modify missing table " + modifies_table_name)
	assert(_entity_prefixes[modifies_table_name] == table_res.entity_prefix,
			"Mod table Prefix/<entity_name> header must match modified table")
	var table_dict: Dictionary = _tables[modifies_table_name]
	assert(table_dict.has(&"name"), "Modified table must have 'name' field")
	var defaults: Dictionary = _table_defaults[modifies_table_name]
	var n_rows: int = _table_n_rows[modifies_table_name]
	var entity_enumeration: Dictionary = _enumeration_dicts[modifies_table_name] # already expanded
	var n_rows_after_mods := entity_enumeration.size()
	var mod_column_names := table_res.column_names
	var mod_row_names := table_res.row_names
	var mod_dict_of_field_arrays := table_res.dict_of_field_arrays
	var mod_prefixes := table_res.db_prefixes
	var mod_types := table_res.db_types
	var mod_import_defaults := table_res.db_import_defaults
	var mod_units := table_res.db_units
	var mod_n_rows := table_res.n_rows
	var precisions_dict: Dictionary
	if _enable_precisions:
		precisions_dict = _precisions[modifies_table_name]
	var unindexing := _get_unindexing(table_res.indexing)
	
	# add new fields (if any) to existing table; default-impute existing rows
	for field in mod_column_names:
		if table_dict.has(field):
			continue
		var prefix: String = mod_prefixes.get(field, "")
		var type: int = mod_types[field]
		var unit: StringName = mod_units.get(field, &"")
		var import_default_idx: int = mod_import_defaults.get(field, 0)
		var import_default_str: String = unindexing[import_default_idx]
		var postprocess_default: Variant = _get_postprocess_value(import_default_str, prefix, type,
				unit)
		var field_type := type if type < TYPE_MAX else TYPE_ARRAY
		var new_field := Array([], field_type, &"", null)
		new_field.resize(n_rows)
		for row in n_rows:
			new_field[row] = postprocess_default
			_count += 1
		table_dict[field] = new_field
		# keep default
		defaults[field] = postprocess_default
		# precisions
		if !_enable_precisions or field_type != TYPE_FLOAT:
			continue
		var new_precisions_array: Array[int] = Array([], TYPE_INT, &"", null)
		new_precisions_array.resize(n_rows)
		new_precisions_array.fill(-1)
		precisions_dict[field] = new_precisions_array
	
	# resize dictionary columns (if needed) imputing default values
	if n_rows_after_mods > n_rows:
		var new_rows := range(n_rows, n_rows_after_mods)
		for field: StringName in table_dict:
			var field_array: Array = table_dict[field]
			field_array.resize(n_rows_after_mods)
			var default: Variant = defaults[field]
			for row: int in new_rows:
				field_array[row] = default
				_count += 1
		_table_n_rows[modifies_table_name] = n_rows_after_mods
		# precisions
		if _enable_precisions:
			for field: StringName in precisions_dict:
				var precisions_array: Array[int] = precisions_dict[field]
				precisions_array.resize(n_rows_after_mods)
				for row: int in new_rows:
					precisions_array[row] = -1
	
	# add/overwrite table values
	for mod_row in mod_n_rows:
		var entity_name := mod_row_names[mod_row]
		var row: int = entity_enumeration[entity_name]
		for field in mod_column_names:
			var prefix: String = mod_prefixes.get(field, "")
			var type: int = mod_types[field]
			var unit: StringName = mod_units.get(field, &"")
			var import_idx: int = mod_dict_of_field_arrays[field][mod_row]
			
			# FIXME: Don't overwrite if 0?
			
			var import_str: String = unindexing[import_idx]
			table_dict[field][row] = _get_postprocess_value(import_str, prefix, type, unit)
			_count += 1
	
	# add/overwrite wiki lookup
	if _enable_wiki:
		for field in mod_column_names:
			if field != localized_wiki:
				continue
			for mod_row in mod_n_rows:
				var import_idx: int = mod_dict_of_field_arrays[field][mod_row]
				if !import_idx: # 0 is empty
					continue
				var import_str: String = unindexing[import_idx]
				var row_name := mod_row_names[mod_row]
				_wiki_lookup[row_name] = _get_postprocess_value(import_str, "", TYPE_STRING_NAME, &"")
	
	# add/overwrite precisions
	if _enable_precisions:
		for field in mod_column_names:
			if mod_types[field] != TYPE_FLOAT:
				continue
#			var mod_precisions_array: Array[int] = mod_precisions[field]
			var precisions_array: Array[int] = precisions_dict[field]
			for mod_row in mod_n_rows:
				var import_value: String = mod_dict_of_field_arrays[field][mod_row]
				var entity_name := mod_row_names[mod_row]
				var row: int = entity_enumeration[entity_name]
				precisions_array[row] = _get_float_str_precision(import_value)


func _postprocess_wiki_lookup(table_res: TableResource) -> void:
	# These are NOT added to the 'tables' dictionary!
	if !_enable_wiki:
		return
	var row_names := table_res.row_names
	var wiki_field: Array[int] = table_res.dict_of_field_arrays[localized_wiki]
	var unindexing := _get_unindexing(table_res.indexing)
	
	for row in table_res.row_names.size():
		var row_name := row_names[row]
		var import_idx := wiki_field[row]
		if !import_idx:
			continue
		var import_str: String = unindexing[import_idx]
		_wiki_lookup[row_name] = _get_postprocess_value(import_str, "", TYPE_STRING, &"")
		_count += 1


func _postprocess_enum_x_enum(table_res: TableResource) -> void:
	var table_array_of_arrays: Array[Array] = []
	var table_name := table_res.table_name
	var row_names := table_res.row_names
	var column_names := table_res.column_names
	var n_import_rows := table_res.n_rows
	var n_import_columns:= table_res.n_columns
	var import_array_of_arrays := table_res.array_of_arrays
	var type: int = table_res.exe_type
	var unit: StringName = table_res.exe_unit
	var import_default_idx: int = table_res.exe_import_default
	var unindexing := _get_unindexing(table_res.indexing)
	
	var row_type := type if type < TYPE_MAX else TYPE_ARRAY
	var import_default_str: String = unindexing[import_default_idx]
	var postprocess_default: Variant = _get_postprocess_value(import_default_str, "", type, unit)
	
	assert(_enumeration_dicts.has(row_names[0]), "Unknown enumeration " + row_names[0])
	assert(_enumeration_dicts.has(column_names[0]), "Unknown enumeration " + column_names[0])
	var row_enumeration: Dictionary = _enumeration_dicts[row_names[0]]
	var column_enumeration: Dictionary = _enumeration_dicts[column_names[0]]
	
	var n_rows := row_enumeration.size() # >= import!
	var n_columns := column_enumeration.size() # >= import!
	
	# size & default-fill postprocess array
	table_array_of_arrays.resize(n_rows)
	for row in n_rows:
		var row_array := Array([], row_type, &"", null)
		row_array.resize(n_columns)
		row_array.fill(postprocess_default)
		table_array_of_arrays[row] = row_array
	
	# overwrite default for specified entities
	for import_row in n_import_rows:
		var row_name := row_names[import_row]
		var row: int = row_enumeration[row_name]
		for import_column in n_import_columns:
			var column_name := column_names[import_column]
			var column: int = column_enumeration[column_name]
			var import_idx: int = import_array_of_arrays[import_row][import_column]
			if !import_idx:
				continue
			var import_str: String = unindexing[import_idx]
			var postprocess_value: Variant = _get_postprocess_value(import_str, "", type, unit)
			_count += 1
			table_array_of_arrays[row][column] = postprocess_value
	
	_tables[table_name] = table_array_of_arrays


func _get_unindexing(indexing: Dictionary) -> Array[String]:
	var unindexing: Array[String] = []
	unindexing.resize(indexing.size())
	for string: String in indexing:
		var idx: int = indexing[string]
		unindexing[idx] = string
	return unindexing


func _get_postprocess_value(import_str: String, prefix: String, type: int, unit: StringName
		) -> Variant:
	
	#if prefix and import_str: # we don't prefix an empty cell!
		#import_str = prefix + import_str
	

	if type == TYPE_BOOL:
		assert(!prefix, "Prefix set for BOOL data")
		if import_str == "x" or import_str.matchn("true"):
			return true
		else:
			assert(import_str == "" or import_str.matchn("false"),
					"Unknown BOOL content '%s'" % import_str)
			return false
	
	if type == TYPE_FLOAT:
		assert(!prefix, "Prefix set for FLOAT data")
		if !import_str:
			return NAN
			
		# WIP: float_constant -> table_constant
		if _float_constants.has(import_str):
			return _float_constants[import_str] # constants are not unit converted!
		
		var unit_split := import_str.split(" ", false, 1)
		if unit_split.size() == 1:
			# Possible "x/unit" needs conversion to "x 1/unit"
			unit_split = import_str.split("/", false, 1)
			if unit_split.size() == 2:
				unit_split[1] = "1/" + unit_split[1]
		if unit_split.size() == 2:
			unit = StringName(unit_split[1]) # overrides column unit!
		
		var float_str := unit_split[0].lstrip("~").replace("E", "e").replace("_", "").replace(",", "")
		assert(float_str.is_valid_float(), 
				"Invalid FLOAT! Before / after postprocessing: '%s' / '%s'" % [
				unit_split[0], float_str])
		
		var import_float := float_str.to_float()
		#var import_float := unit_split[0].lstrip("~").to_float()
		if unit:
			return IVQConvert.convert_quantity(import_float, unit, true, true)
		return import_float
	
	if type == TYPE_STRING:
		if !import_str:
			return ""
		if prefix:
			import_str = prefix + import_str
		import_str = import_str.c_unescape() # does not process '\uXXXX'
		import_str = c_unescape_patch(import_str)
		return import_str
	
	if type == TYPE_STRING_NAME:
		if !import_str:
			return &""
		if prefix:
			import_str = prefix + import_str
		return StringName(import_str)
	
	if type == TYPE_INT: # imported as StringName for enumerations
		if !import_str:
			return -1
		if prefix:
			import_str = prefix + import_str
		if import_str.is_valid_int():
			return import_str.to_int()
		assert(_enumerations.has(import_str), "Unknown enumeration " + import_str)
		return _enumerations[import_str]
	
	if type >= TYPE_MAX:
		var array_type := type - TYPE_MAX
		assert(array_type < TYPE_MAX and array_type != TYPE_ARRAY, "Nested array not allowed")
		var array := Array([], array_type, &"", null)
		if !import_str:
			return array # empty typed array
		var import_array := import_str.split(",")
		for import_element in import_array:
			array.append(_get_postprocess_value(import_element, prefix, array_type, unit))
		return array
	
	assert(false, "Unsupported type %s" % type)
	return null


func _get_float_str_precision(float_str: String) -> int:
	# Based on preprocessed strings from table_resource.gd.
	# We ignore an inline unit, if present.
	# We ignore leading zeroes.
	# We count trailing zeroes IF AND ONLY IF the number has a decimal place.
	if _float_constants.has(float_str):
		var float_value: float = _float_constants[float_str]
		if is_nan(float_value) or is_inf(float_value):
			return -1
		# There's no way to know precision of a constant. Only astronomy geeks
		# are using precision anyway, so this shouldn't be an issue. Return
		# a 3 so something shows up in GUI.
		return 3
	if float_str.begins_with("~"):
		return 0 # in Planetarium GUI we display these as, e.g., '~1 km'
	
	# replicate postprocessing string changes
	var unit_split := float_str.split(" ", false, 1)
	unit_split = unit_split[0].split("/", false, 1)
	float_str = unit_split[0]
	float_str = float_str.replace("E", "e").replace("_", "").replace(",", "")
	
	# calculate precision
	var length := float_str.length()
	var n_digits := 0
	var started := false
	var n_unsig_zeros := 0
	var deduct_zeroes := true
	var i := 0
	while i < length:
		var chr: String = float_str[i]
		if chr == ".":
			started = true
			deduct_zeroes = false
		elif chr == "e":
			break
		elif chr == "0":
			if started:
				n_digits += 1
				if deduct_zeroes:
					n_unsig_zeros += 1
		elif chr != "-":
			assert(chr.is_valid_int(), "Unknown FLOAT character '%s' in %s" % [chr, float_str])
			started = true
			n_digits += 1
			n_unsig_zeros = 0
		i += 1
	if deduct_zeroes:
		n_digits -= n_unsig_zeros
	return n_digits
