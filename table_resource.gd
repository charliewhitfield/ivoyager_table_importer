# table_resource.gd
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
extends Resource

# The resourse only needs to be loaded for data postprocessing by
# table_postprocessor.gd. After that, all processed table data is available in
# autoload singleton 'IVTableData' (table_data.gd). The resourses are
# de-referenced so they free themselves and go out of memory.
#
# Data here is preprocessed for compactness and for the needs of the
# postprocessor. It isn't very usefull in its preprocessed form.

enum TableDirectives {
	# table formats
	DB_ENTITIES,
	DB_ENTITIES_MOD,
	ENUMERATION,
	WIKI_LOOKUP,
	ENUM_X_ENUM,
	N_TABLE_FORMATS,
	# specific directives
	MODIFIES,
	TABLE_TYPE,
	TABLE_DEFAULT,
	TABLE_UNIT,
	TRANSPOSE,
	# any file
	DONT_PARSE, # do nothing (for debugging or under-construction table)
}

const ALLOWED_SPECIFIC_DIRECTIVES := [
	# List for each table format (we don't need DONT_PARSE here).
	[],
	[TableDirectives.MODIFIES],
	[],
	[],
	[TableDirectives.TABLE_TYPE, TableDirectives.TABLE_DEFAULT, TableDirectives.TABLE_UNIT,
			TableDirectives.TRANSPOSE],
]

const REQUIRES_ARGUMENT := [false, false, false, false, false, false,
		true, true, true, true, false, false]

const TableUtils := preload("res://addons/ivoyager_table_importer/table_utils.gd")


@export var table_format := -1
@export var table_name := &""
@export var specific_directives: Array[int] = []
@export var specific_directive_args: Array[String] = []

# For vars below, content depends on table format:
#  - All have 'n_rows' & 'n_columns'
#  - ENUMERATION has 'row_names' & 'entity_prefix'
#  - WIKI_LOOKUP has 'column_names', 'row_names' & 'dict_of_field_arrays'
#  - DB_ENTITIES has 'column_names', [optionally 'row_names'] & all under 'db style'
#  - DB_ENTITIES_MOD has above (always 'row_names') plus 'modifies_table_name'
#  - ENUM_X_ENUM has 'column_names', 'row_names' & all under 'enum x enum'

@export var column_names: Array[StringName] # fields if applicable
@export var row_names: Array[StringName] # entities if applicable
@export var n_rows := -1
@export var n_columns := -1 # not counting row_names (e.g., 0 for ENUMERATION)
@export var entity_prefix := "" # only if header has Prefix/<entity prefix>
@export var modifies_table_name := &"" # DB_ENTITIES_MOD only

# db style
@export var dict_of_field_arrays: Dictionary # preprocessed data indexed [field][row]
@export var postprocess_types: Dictionary # ints indexed [field]
@export var default_values: Dictionary # preprocessed data indexed [field] (if Default exists)
@export var unit_names: Dictionary # StringNames indexed [field] (FLOAT fields if Unit exists)

# enum x enum
@export var array_of_arrays: Array[Array] # preprocessed data indexed [row_enum][column_enum]
@export var enum_x_enum_info: Array # [postprocess_type, unit_name, import_default]

# path for debug asserts
@export var path: String

# indexing
@export var str_indexing := {"" : 0} # empty is always idx 0
var next_idx := 1


func import_file(file: FileAccess, source_path: String) -> void:
	path = source_path

	# store data cells and set table_format
	var cells: Array[Array] = []
	var comment_columns: Array[int] = []
	var n_data_columns: int
	var file_length := file.get_length()
	while file.get_position() < file_length:
		var file_line := file.get_line()
		
		# skip comment lines
		if file_line.begins_with("#") or file_line.begins_with('"#') or file_line.begins_with("'#"):
			continue
		
		# get line into array and do quote processing
		var line_split := file_line.split("\t") # PackedStringArray, but we want an Array
		var line_array: Array[String] = Array(Array(line_split), TYPE_STRING, &"", null)
		for i in line_array.size():
			if line_array[i].begins_with('"') and line_array[i].ends_with('"'):
				line_array[i] = line_array[i].lstrip('"').rstrip('"')
			if line_array[i].begins_with("'"):
				line_array[i] = line_array[i].lstrip("'")
		
		# handle or store directives
		if line_array[0].begins_with("@"):
			var directive_str := line_array[0].trim_prefix("@")
			assert(TableDirectives.has(directive_str),
				"Unknown table directive %s in %s" % [line_array[0], path])
			var directive: int = TableDirectives[directive_str]
			if directive == TableDirectives.DONT_PARSE:
				return
			var directive_arg := line_array[1] if line_array.size() > 1 else ""
			if directive < TableDirectives.N_TABLE_FORMATS:
				assert(table_format == -1, ">1 format specified in " + path)
				table_format = directive
				if directive_arg: # otherwise, we'll get table name from file name
					table_name = StringName(directive_arg)
			else:
				assert(directive > TableDirectives.N_TABLE_FORMATS,
						"Don't use @N_TABLE_FORMATS in " + path)
				specific_directives.append(directive)
				specific_directive_args.append(directive_arg)
			continue
		
		# identify comment columns in 1st non-comment, non-directive row (fields, if we have them)
		if !cells:
			n_data_columns = line_array.size()
			for column in line_array.size():
				if line_array[column].begins_with("#"):
					comment_columns.append(column)
					n_data_columns -= 1
			comment_columns.reverse() # we'll remove from back
		
		# remove comment columns in all rows
		for comment_column in comment_columns: # back to front
			line_array.remove_at(comment_column)
		assert(line_array.size() == n_data_columns,
			"Inconsistent row column number after tab delimination in " + path)
		cells.append(line_array)
	
	# set format and/or name if not specified in directive
	if table_format == -1:
		if n_data_columns == 1:
			table_format = TableDirectives.ENUMERATION
		elif specific_directives.has(TableDirectives.MODIFIES):
			table_format = TableDirectives.DB_ENTITIES_MOD
		else:
			table_format = TableDirectives.DB_ENTITIES
	if !table_name:
		table_name = StringName(path.get_file().get_basename())
	
	# directive error check
	var allowed_directives: Array = ALLOWED_SPECIFIC_DIRECTIVES[table_format]
	for i in specific_directives.size():
		var directive := specific_directives[i]
		assert(allowed_directives.has(directive),
				"Unallowed directive %s in format %s in %s" % [directive, table_format, path])
		assert(!REQUIRES_ARGUMENT[directive] or specific_directive_args[i],
				"Directive %s requires an argument in %s" % [directive, path])
	
	# send cells for preprocessing
	match table_format:
		TableDirectives.DB_ENTITIES:
			_preprocess_db_style(cells, false, false, false)
		TableDirectives.DB_ENTITIES_MOD:
			_preprocess_db_style(cells, true, false, false)
		TableDirectives.ENUMERATION:
			_preprocess_db_style(cells, false, true, false)
		TableDirectives.WIKI_LOOKUP:
			_preprocess_db_style(cells, false, false, true)
		TableDirectives.ENUM_X_ENUM:
			_preprocess_enum_x_enum(cells)


func _preprocess_db_style(cells: Array[Array], is_mod: bool, is_enumeration: bool,
		is_wiki_lookup: bool) -> void:
	
	# specific directives
	var modifies_pos := specific_directives.find(TableDirectives.MODIFIES)
	if modifies_pos >= 0:
		modifies_table_name = StringName(specific_directive_args[modifies_pos])
	
	# dictionaries we'll populate
	if !is_enumeration:
		dict_of_field_arrays = {}
		if !is_wiki_lookup:
			postprocess_types = {} # indexed by fields
			default_values = {} # indexed by fields
			unit_names = {} # indexed by FLOAT fields
#			precisions  = {} # structured as dict_of_field_arrays but only FLOAT fields
	
	# temp working dicts
	var prefixes := {}
	var raw_defaults := {}
	
	var n_cell_rows := cells.size()
	var n_cell_columns := cells[0].size()
	var skip_column_0_iterator := range(1, n_cell_columns)
	var row := 0
	var content_row := 0
	var is_header := true
	var has_types := false
	var has_row_names := false
	
	# handle field names
	if !is_enumeration:
		var line_array: Array[String] = cells[0]
		assert(!line_array[0], "Left-most cell of field name header must be empty in " + path)
		column_names = []
		for column in skip_column_0_iterator:
			var field := StringName(line_array[column])
			assert(field != &"name", "Use of 'name' as field is not allowed in " + path)
			assert(!column_names.has(field), "Duplicate field name " + field)
			if is_wiki_lookup:
				assert(field.ends_with(".wiki"),
						"WIKI_LOOKUP fields must be 'en.wiki', etc. in " + path)
			column_names.append(field)
		row += 1
	
	# process rows after field names
	while row < n_cell_rows:
		
		var line_array: Array[String] = cells[row]
		
		# header
		if is_header:
			# process header rows until we don't recognize line_array[0] as header item
			if line_array[0] == "Type":
				assert(!is_enumeration,
						"'Type' doesn't belong in ENUMERATION table format in " + path)
				assert(!is_wiki_lookup,
						"'Type' doesn't belong in WIKI_LOOKUP table format in " + path)
				for column in skip_column_0_iterator:
					assert(line_array[column], "All fields must have 'Type' in " + path)
					var field := column_names[column - 1]
					postprocess_types[field] = _get_postprocess_type(line_array[column])
				has_types = true
				row += 1
				continue
			
			if line_array[0] == "Unit":
				assert(!is_enumeration,
						"'Unit' doesn't belong in ENUMERATION table format in " + path)
				assert(!is_wiki_lookup,
						"'Unit' doesn't belong in WIKI_LOOKUP table format in " + path)
				for column in skip_column_0_iterator:
					if line_array[column]: # is non-empty
						var field := column_names[column - 1]
						unit_names[field] = StringName(line_array[column]) # verify is FLOAT below
				row += 1
				continue
			
			if line_array[0] == "Default":
				assert(!is_enumeration,
						"'Default' doesn't belong in ENUMERATION table format in " + path)
				assert(!is_wiki_lookup,
						"'Default' doesn't belong in WIKI_LOOKUP table format in " + path)
				for column in skip_column_0_iterator:
					if line_array[column]: # is non-empty
						var field := column_names[column - 1]
						raw_defaults[field] = line_array[column] # preprocess below
				row += 1
				continue
			
			if line_array[0].begins_with("Prefix"):
				if line_array[0].length() > 6:
					assert(line_array[0][6] == "/",
							"Bad Prefix construction %s in %s" % [line_array[0], path])
					entity_prefix = line_array[0].trim_prefix("Prefix/")
				for column in skip_column_0_iterator:
					if line_array[column]: # is non-empty
						var field := column_names[column - 1]
						prefixes[field] = line_array[column]
				row += 1
				continue
			
			# header finished!
			n_rows = n_cell_rows - row
			assert(has_types or is_enumeration or is_wiki_lookup,
					"Table format requires 'Type' in " + path)
			for field in unit_names:
				assert(postprocess_types[field] == TYPE_FLOAT,
						"Only FLOAT can have Unit in " + path)
			
			# preprocess defaults
			for field in raw_defaults:
				var raw_default: String = raw_defaults[field]
				var prefix: String = prefixes.get(field, "")
				var postprocess_type: int = postprocess_types[field]
				default_values[field] = _get_preprocess_value(raw_default, postprocess_type, prefix)
			
			# init arrays in dictionaries
			for field in column_names: # none if is_enumeration
				var preprocess_type: int
				if !is_wiki_lookup:
					var postprocess_type: int = postprocess_types[field]
					preprocess_type = _get_preprocess_type(postprocess_type)
				else:
					preprocess_type = TYPE_INT
				var field_array := Array([], preprocess_type, &"", null)
				field_array.resize(n_rows)
				dict_of_field_arrays[field] = field_array
		
			is_header = false
		
		# process content row
		if content_row == 0:
			if line_array[0]:
				has_row_names = true
				row_names = []
			else:
				assert(!is_mod and !is_enumeration and !is_wiki_lookup,
						"Missing required row name in " + path)
		elif has_row_names:
			assert(line_array[0], "Missing expected row name in " + path)
		else:
			assert(!line_array[0],
					"Inconsistent use of row name; must be all or none in " + path)
		
		if has_row_names:
#			var prefix: String = prefixes.get(&"name", "")
			var row_name := StringName(entity_prefix + line_array[0])
			assert(!row_names.has(row_name))
			row_names.append(row_name)
			if is_enumeration: # we only needed row name
				content_row += 1
				row += 1
				continue
#			dict_of_field_arrays[&"name"][content_row] = row_name
		
		# process content columns
		for column in skip_column_0_iterator:
			var field := column_names[column - 1]
			var raw_value: String = line_array[column]
			var preprocess_value: Variant
			if !raw_value and default_values.has(field):
				preprocess_value = default_values[field]
			else:
				var prefix: String = prefixes.get(field, "")
				var postprocess_type: int = (TYPE_STRING_NAME if is_wiki_lookup
						else postprocess_types[field])
				preprocess_value = _get_preprocess_value(raw_value, postprocess_type, prefix)
			dict_of_field_arrays[field][content_row] = preprocess_value
		content_row += 1
		row += 1
	
	n_columns = 0 if is_enumeration else dict_of_field_arrays.size()


func _preprocess_enum_x_enum(cells: Array[Array]) -> void:
	
	var n_cell_rows := cells.size() # includes column_names
	var n_cell_columns := cells[0].size() # includes row_names
	n_rows = n_cell_rows - 1
	n_columns = n_cell_columns - 1
	
	# get prefixes
	var row_prefix := ""
	var column_prefix := ""
	if cells[0][0]:
		var prefixes: String = cells[0][0]
		var prefixes_split := prefixes.split("\\")
		assert(prefixes_split.size() == 2,
				"To prefix, use <row prefix>\\<column prefix> in " + path)
		row_prefix = prefixes_split[0]
		column_prefix = prefixes_split[1]
	
	# apply directives
	var type_pos := specific_directives.find(TableDirectives.TABLE_TYPE)
	assert(type_pos >= 0, "Table format requires @TABLE_TYPE in " + path)
	var raw_type := specific_directive_args[type_pos]
	var postprocess_type := _get_postprocess_type(raw_type)
	var raw_default := ""
	var default_pos := specific_directives.find(TableDirectives.TABLE_DEFAULT)
	if default_pos >= 0:
		raw_default = specific_directive_args[default_pos]
	var import_default: Variant = _get_preprocess_value(raw_default, postprocess_type, "")
	var unit_pos := specific_directives.find(TableDirectives.TABLE_UNIT)
	var unit_name := &""
	if unit_pos >= 0:
		assert(postprocess_type == TYPE_FLOAT, "Can't use @TABLE_UNIT for non-FLOAT in " + path)
		unit_name = StringName(specific_directive_args[unit_pos])
	if specific_directives.has(TableDirectives.TRANSPOSE):
		var swap_prefix := row_prefix
		row_prefix = column_prefix
		column_prefix = swap_prefix
		var swap_data: Array[Array] = []
		swap_data.resize(n_cell_columns)
		for i in n_cell_columns:
			var swap_row: Array[String] = []
			swap_row.resize(n_cell_rows)
			swap_data[i] = swap_row
			for j in n_cell_rows:
				swap_data[i][j] = cells[j][i]
		cells = swap_data
		n_cell_rows = cells.size()
		n_cell_columns = cells[0].size()
		n_rows = n_cell_rows - 1
		n_columns = n_cell_columns - 1
	
	# init all arrays
	row_names = []
	row_names.resize(n_rows)
	column_names = []
	column_names.resize(n_columns)
	var skip_column_0_iterator := range(1, n_cell_columns)
	array_of_arrays = []
	array_of_arrays.resize(n_rows)
	var row_array := []
	row_array.resize(n_columns)
	for i in n_rows:
		array_of_arrays[i] = row_array.duplicate()
	
	# set column names
	var line_array: Array[String] = cells[0]
	for column in skip_column_0_iterator:
		column_names[column - 1] = StringName(column_prefix + line_array[column])
	
	# process data rows
	var row := 1
	while row < n_cell_rows:
		line_array = cells[row]
		row_names[row - 1] = StringName(row_prefix + line_array[0])
		for column in skip_column_0_iterator:
			var raw_value := line_array[column]
			var preprocess_value: Variant
			if raw_value:
				preprocess_value = _get_preprocess_value(raw_value, postprocess_type, "")
			else:
				preprocess_value = import_default
			array_of_arrays[row - 1][column - 1] = preprocess_value
		row += 1
	
	# set table info
	enum_x_enum_info = [postprocess_type, unit_name, import_default]


func _get_postprocess_type(type_str: StringName) -> int:
	# Array types are encoded using int values >= TYPE_MAX
	if type_str == &"FLOAT":
		return TYPE_FLOAT
	if type_str == &"BOOL":
		return TYPE_BOOL
	if type_str == &"INT":
		return TYPE_INT
	if type_str == &"STRING":
		return TYPE_STRING
	if type_str == &"STRING_NAME":
		return TYPE_STRING_NAME
	if type_str.begins_with("ARRAY[") and type_str.ends_with("]"):
		var array_type := _get_postprocess_type(type_str.trim_prefix("ARRAY[").trim_suffix("]"))
		return TYPE_MAX + array_type
	assert(false, "Missing or unknown table Type '%s' in %s" % [type_str, path])
	return -1


func _get_preprocess_type(postprocess_type: int) -> int:
	if postprocess_type == TYPE_FLOAT:
		return TYPE_STRING
	if postprocess_type >= TYPE_MAX:
		return TYPE_ARRAY
	return TYPE_INT


func _get_preprocess_value(value: String, postprocess_type: int, prefix: String) -> Variant:
	# Return is appropriate 'preprocess' type.
	
	match postprocess_type:
		TYPE_BOOL:
			if value == "x" or value.matchn("true"):
				return 1
			assert(value == "" or value.matchn("false"),
					"Unknown BOOL content '%s' in %s" % [value, path])
			return 0
		
		TYPE_FLOAT:
			# Store as a string so postprocessor can determine precision.
			if value == "" or value.matchn("nan"):
				return ""
			if value == "?" or value.matchn("inf"):
				return "?"
			if value == "-?" or value.matchn("-inf"):
				return "-?"
			value = value.replace("E", "e").replace("_", "")
			assert(value.lstrip("~").is_valid_float(), "Invalid float '%s' in %s" % [value, path])
			return value
		
		TYPE_STRING, TYPE_STRING_NAME, TYPE_INT:
			# Index all text types; INTs are often enumerations.
			if value == "":
				return 0
			if prefix:
				return _get_str_index(prefix + value)
			return _get_str_index(value)
	
	if postprocess_type >= TYPE_MAX: # value encodes an array
		var content_type := postprocess_type - TYPE_MAX
		assert(content_type < TYPE_MAX, "Nested array type? " + path)
		assert(content_type != TYPE_ARRAY, "Nested array type? " + path)
		var content_import_type := _get_preprocess_type(content_type)
		var result_array := Array([], content_import_type, &"", null)
		if !value:
			return result_array
		var raw_array := value.split(",")
		for raw_element in raw_array:
			result_array.append(_get_preprocess_value(raw_element, content_type, prefix))
		return result_array
	
	assert(false, "Missing or unknown type '%s' in %s" % [postprocess_type, path])
	return null


func _get_str_index(value: String) -> int:
	var idx: int = str_indexing.get(value, -1)
	if idx == -1:
		idx = next_idx
		str_indexing[value] = idx
		next_idx += 1
	return idx

