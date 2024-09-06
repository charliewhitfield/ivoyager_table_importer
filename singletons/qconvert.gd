# qconvert.gd
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

# This node is added as singleton "IVQConvert".
#
# Converts float quantities to or from internal units.

const DPRINT := false

var unit_multipliers: Dictionary = IVUnits.unit_multipliers
var unit_lambdas: Dictionary = IVUnits.unit_lambdas



func is_valid_unit(unit: StringName, parse_compound_unit := false) -> bool:
	# Tests whether 'unit' string is valid for convert_quantity().
	return !is_nan(convert_quantity(1.0, unit, true, parse_compound_unit, false))


func convert_quantity(x: float, unit: StringName, to_internal := true,
		parse_compound_unit := true, assert_error := true) -> float:
	# Converts 'x' in specified 'unit' to internal float value, or from
	# internal value if to_internal == false. Will attempt to parse the 'unit'
	# string if parse_compound_unit == true. Throws an error if 'unit' is not
	# present in conversion dictionaries or it can't be parsed, or returns NAN
	# if assert_error == false.
	#
	# If 'unit' is in 'unit_multipliers' or 'unit_lambdas', then no parsing is
	# attempted. Dictionary 'unit_multipliers' can have compound units like
	# 'm/s^2' for quick lookup without parsing.
	#
	# If a unit string is parsed, then the unit name and multiplier will be
	# added to 'unit_multipliers' as a key-value pair. This greately speeds up
	# subsequent usage and makes the unit string directly accessible in the 
	# dictionary (e.g., by GUI).
	#
	# See parsing comments in get_parsed_unit_multiplier().
	if !unit:
		return x
	
	var multiplier: float = unit_multipliers.get(unit, 0.0)
	if multiplier:
		return x * multiplier if to_internal else x / multiplier
	
	if unit_lambdas.has(unit):
		var lambda: Callable = unit_lambdas[unit]
		return lambda.call(x, to_internal)
	
	if !parse_compound_unit:
		assert(!assert_error,
				"'%s' is not in unit_multipliers or unit_lambdas dictionaries" % unit)
		return NAN
	
	multiplier = get_parsed_unit_multiplier(unit, assert_error)
	
	unit_multipliers[unit] = multiplier # for direct access in subsequent usage!
	
	return x * multiplier if to_internal else x / multiplier


func get_parsed_unit_multiplier(unit_str: String, assert_error: bool) -> float:
	# Parsing isn't super fast. But once encountered by convert_quantity(), the
	# unit name will be added to the 'unit_multipliers' dictionary for quick
	# subsequent usage.
	#
	# Parser rules:
	#
	#   1. The compound unit string must be composed only of valid multiplier
	#      units (i.e., in 'unit_multiplier' dictionary), valid float numbers,
	#      unit operators, and parentheses '(' and ')'.
	#   2. Allowed unit operatiors are "^", "/", and " ", corresponding to
	#      exponentiation, division and multiplication, in that order of
	#      precidence.
	#   3. Operators must have a valid non-operator substring on each side
	#      without adjacent spaces. Spaces are ONLY allowed as multiplication
	#      operators.
	#   4. Each parenthesis opening '(' must have a closing ')'.
	#
	# Example valid unit strings for parsing:
	#
	#   m/s^2
	#   m^3/(kg s^2)
	#   1e24
	#   10^24
	#   10^24 kg
	#   1/d
	#   d^-1
	#   m^0.5
	
	# debug print unit strings & substrings
	if DPRINT:
		print(unit_str)
	
	if !unit_str:
		assert(!assert_error, "Empty unit string or substring. This could be caused by a"
				+ " disallowed space that is not a multiplication operator.")
		return NAN
	
	var multiplier: float = unit_multipliers.get(unit_str, 0.0)
	if multiplier:
		return multiplier
	
	if unit_str.is_valid_float():
		return unit_str.to_float()
	
	var length := unit_str.length()
	var position := 0
	var enclosure_level := 0
	
	# check for matching enclosure parentheses
	if unit_str[0] == "(":
		position = 1
		enclosure_level = 1
		while position < length:
			var chr := unit_str[position]
			if chr == "(":
				enclosure_level += 1
			elif chr == ")":
				enclosure_level -= 1
				if enclosure_level == 0:
					if position == length - 1:
						return get_parsed_unit_multiplier(
								unit_str.trim_prefix("(").trim_suffix(")"), assert_error)
					break # opening '(' matched before the end
				if enclosure_level < 0:
					assert(!assert_error,
							"Unmatched ')' in unit string or substring '%s'" % unit_str)
					return NAN
			position += 1
	
	# multiply two parts on non-enclosed " "
	if unit_str.find(" ") != -1:
		position = 0
		enclosure_level = 0
		while position < length:
			var chr := unit_str[position]
			if chr == "(":
				enclosure_level += 1
			elif chr == ")":
				enclosure_level -= 1
			elif chr == " " and enclosure_level == 0:
				return (get_parsed_unit_multiplier(unit_str.left(position), assert_error)
						* get_parsed_unit_multiplier(unit_str.substr(position + 1), assert_error))
			position += 1
	
	# divide two parts on non-enclosed "/"
	if unit_str.find("/") != -1:
		position = 0
		enclosure_level = 0
		while position < length:
			var chr := unit_str[position]
			if chr == "(":
				enclosure_level += 1
			elif chr == ")":
				enclosure_level -= 1
			elif chr == "/" and enclosure_level == 0:
				return (get_parsed_unit_multiplier(unit_str.left(position), assert_error)
						/ get_parsed_unit_multiplier(unit_str.substr(position + 1), assert_error))
			position += 1
	
	# exponentiate two parts on non-enclosed "^"
	if unit_str.find("^") != -1:
		position = 0
		enclosure_level = 0
		while position < length:
			var chr := unit_str[position]
			if chr == "(":
				enclosure_level += 1
			elif chr == ")":
				enclosure_level -= 1
			elif chr == "^" and enclosure_level == 0:
				return pow(get_parsed_unit_multiplier(unit_str.left(position), assert_error),
						 get_parsed_unit_multiplier(unit_str.substr(position + 1), assert_error))
			position += 1
	
	assert(!assert_error, "Could not parse unit string or substring '%s'" % unit_str)
	return NAN
