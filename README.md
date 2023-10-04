# I, Voyager - Table Importer

TL;DR: This Godot Editor plugin imports tables like [this](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv) and provides access to processed, statically typed data. It imputes defaults, prefixes strings, converts floats by specified units, and converts text enumerations to integers (enumerations can be project or table-defined), ... amongst other things. 

## Installation

Find more detailed instructions at our [Developers Page](https://www.ivoyager.dev/developers/).

The plugin directory `ivoyager_table_importer` should be added _directly to your addons directory_*. You can do this one of two ways:

1. Download and extract the plugin, then add it (in its entirety) to your addons directory, creating an 'addons' directory in your project if needed.
2. (Recommended) Add as a git submodule. From your project directory, use git command:  
    `git submodule add https://github.com/ivoyager/ivoyager_table_importer addons/ivoyager_table_importer`  
    This method will allow you to version-control the plugin from within your project rather than moving directories manually. You'll be able to pull updates, checkout any commit, or submit pull requests back to us. This does require some learning to use git submodules. (We use [GitKraken](https://www.gitkraken.com/) to make this easier!)

(*Note: This differs from Godot's recomended plugin distribution from inside an empty project, but allows us to version-control our plugins without manual directory operations.)

Then enable 'I, Voyager - Table Importer' from Godot Editor menu: Project / Project Settings / Plugins. The plugin will provide an autoload singleton called 'IVTableData' through which you can provide postprocessing intructions and interact with processed table data.

## Overview

This plugin is maintained for [I, Voyager's](https://github.com/ivoyager) solar system simulator and associated apps and games. It's powerful but requires very specific file formatting. It's not meant to be a general 'read any' table utility.

It provides several specific table file formats that allow:
* Specification of data `Type` so that all table values are correctly converted to statically typed internal values.
* Specification of data `Default` to reduce table clutter. Fields that are mostly a particular value can be left mostly empty.
* Specification of data `Prefix` to reduce enumeration text size. E.g., shorten 'PLANET_MERCURY', 'PLANET_VENUS', 'PLANET_EARTH' to 'MERCURY', 'VENUS', 'EARTH'.
* Specification of float `Unit` so file data can be entered in the most convenient units while maintaining consistent internal representation.
* Table **enumerations** that may reference project enums _**or**_ table-defined entity names. For example, in our project, 'PLANET_EARTH' resolves to 3 as an integer _in any table_ because 'PLANET_EARTH' is row 3 in planets.tsv.
* 'Mod' tables that modify existing tables.
* [Optionally] Construction of a wiki lookup dictionary to use for an internal or external wiki.
* [For scientific apps, mostly] Determination of float significant digits from file number text, so precision can be correctly displayed even after unit conversion.
* Easy or optimized access to _all_ processed and statically typed data via the IVTableData singleton.

File and table formats are described below.

## Usage

All user interface is via an autoload singleton **IVTableData** added by the plugin. From here you will give postprocessing intructions and access all postprocessed table data. IVTableData also provides functions to build objects, dictionaries, or flag fields directly from table data. See API in [table_data.gd](https://github.com/ivoyager/ivoyager_table_importer/blob/master/table_data.gd).

Postprocessing is controled by function:

`postprocess_tables(table_names: Array, project_enums := [], unit_multipliers := {}, unit_lambdas := {}, enable_wiki := false, enable_precisions := false)`

The plugin imports .tsv tables as a custom resource class that contains low-level, preprocessed data that isn't very useful except for table debugging.

## General File Format and Table Editing

#### Delimiter and File Extension

We support only tab-delimited files with extension 'tsv'.

#### Table Directives

Any line starting with '@' is read as a table directive, which is used to specify one of several table formats and provide additional format-specific instructions. These can be at any line in the file. It may be convenient to include these at the end as many table viewers (including GitHub web pages) assume field names in the top line.

Table format is specified by one of `@DB_ENTITIES` (default), `@DB_ENTITIES_MOD`, `@DB_ANONYMOUS_ROWS`, `@ENUMERATION`, `@WIKI_LOOKUP`, or `@ENUM_X_ENUM`, optionally followed by '=' and then the table name. If omitted, table name is taken from the base file name (e.g., 'planets' for 'res://path/planets.tsv' file). Several table formats don't need a table format specifier as the importer can figure it out from other clues. Some table formats allow or require additional specific directives. See details in format sections below. (' = ' is always ok in place of '='.)

For debugging or work-in-progress, you can prevent any imported table from being processed using `@DONT_PARSE`.

#### Comments

Any line starting with '#' is ignored. Additionally, entire columns are ignored if the column 'field' name begins with '#'.

#### Cell Processing

All cells have some processing on import before Type-processing described below:
* Double-quotes (") will be removed if they enclose the cell on both sides.
* A prefix single-quote ('), if present, will be removed.

#### Table Editor Warning!

Most .csv/.tsv file editors will 'interpret' and change your table data, especially any values that look like numbers or dates. For example, Excel will change '1.32712440018e20' to '1.33E+20' in your saved file without warning! One editor that does NOT change your data is [Rons Data Edit](https://www.ronsplace.ca/Products/RonsDataEdit). It's free for files with up to 1000 rows, or pay for 'pro' unlimited.

## DB_ENTITIES Format

[Example Table](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv)

Optional specifier: `@DB_ENTITIES[=<table_name>]` (table_name defaults to the base file name)  
Optional directive: `@DONT_PARSE`

This is the default table format assumed by the importer if other conditions (described under formats below) don't exist. The format has database-style entities (as rows) and fields (as columns). The first column of each row is taken as an 'entity name' and used to create an implicit 'name' field. Entity names are treated as enumerations and are accessible in other tables if the enumeration name appears in a field with Type=INT. Entity names must be globally unique.

Processed data are structured as a dictionary-of-statically-typed-field-arrays. Access the dictionary directly or use 'get' methods in IVTableData.

#### Header Rows

The first non-comment, non-directive line is assumed to hold the field names. The left-most cell must be empty.

After field names and before data, tables can have the following header rows in any order:
* `Type` (required) with column values:
   * `STRING` - Data processing applies Godot escaping such as \n, \t, etc. We also convert unicode '\u' escaping  up to \uFFFF (but not '\U' escaping for larger unicodes). Empty cells will be imputed with `Default` or "".
   * `STRING_NAME` - No escaping. Empty cells will be imputed with `Default` or &"".
   * `BOOL` - Case-insensitive 'True' or 'False'. 'x' (lower case) is interpreted as True. Empty cells will be imputed with `Default` or False. Any other cell values will cause an error.
   * `INT` - A valid integer or text 'enumeration'. Enumerations may include any table entity name (from _any_ table) or hard-coded project enums specified in the `postprocess_tables()` call (enumerations that can't be found will cause an error at this function call). Empty cells will be imputed with `Default` or -1.
   * `FLOAT` - 'INF', '-INF' and 'NAN' (case-insensitive) are correctly interpreted. '?' and '-?' are interpreted as INF and -INF, respectively. 'E' or 'e' are ok. Underscores '_' are allowed and removed before float conversion. A '~' prefix is allowed and affects precision (see below) but not float value. Empty cells will be imputed with `Default` or NAN.
   * `ARRAY[xxxx]` (where 'xxxx' specifies element type and is any of the above types) - The cell will be split by ',' (no space) and each element interpreted exactly as its type above. Column `Unit` and `Prefix`, if specified, are applied element-wise. Empty cells will be imputed with `Default` or an empty, typed array.
* `Default` (optional): Default values must be empty or follow Type rules above. If non-empty, this value is imputed for any empty cells in the column.
* `Unit` (optional; FLOAT fields only): The data processor recognizes a broad set of unit symbols (mostly but not all SI) and, by default, converts table floats to SI base units in the postprocessed 'internal' data. Default unit conversions are defined by 'unit_multipliers' and 'unit_lambdas' dictionaries [here](https://github.com/charliewhitfield/ivoyager_table_importer/blob/develop/table_unit_defaults.gd). Unit symbols and/or internal representation can be changed by specifying replacement conversion dictionaries in the `postprocess_tables()` call.
* `Prefix` (optional; STRING, STRING_NAME and INT fields only): Prefixes any non-empty cells and `Default` (if specified) with provided prefix text. To prefix the column 0 implicit 'name' field, use `Prefix/<entity prefix>`. E.g., we use `Prefix/PLANET_` in [planets.tsv](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv) to prefix all entity names with 'PLANET_'.

#### Entity Names

The left-most 0-column of each content row specifies an 'entity name'. Entity names are included in an implicit field called 'name' with Type=STRING_NAME. Prefix can be specified for the 0-column using header `Prefix/<entity prefix>`. Entity names (after prefixing) must be globally unique. They can be used in _any_ table as an enumeration that evaluates to the row number (INT) in the defining table. You can obtain row_number from the 'enumerations' dictionary (index with any entity name) or obtain an enum-like dictionary of entity names from the 'enumeration_dicts' dictionary (index with table_name or any entity_name) or obtain a enumeration array of entity names from the 'enumeration_arrays' dictionary.

#### Wiki

To create a wiki lookup dictionary, specify `enable_wiki = true` in the `postprocess_tables()` call. The postprocessor will populate the 'wiki_lookup' dictionary in IVTableData from any columns named 'en.wiki' in your table. (TODO: localization for 'fr.wiki', 'de.wiki', etc...)

For example usage, our [Planetarium](https://www.ivoyager.dev/planetarium/) uses this feature to create hyperlink text to Wikipedia.org pages for almost all table entities: e.g., 'Sun', 'Ceres_(dwarf_planet)', 'Hyperion_(moon)', etc. Alternatively, the lookup could be used for an internal game wiki.

#### Float Precision

For scientific or educational apps it is important to know and correctly represent data precision in GUI. To obtain a float value's original file precision in significant digits, specify `enable_precisions = true` in the `postprocess_tables()` call. You can then access float precisions via the 'precisions' dictionary or 'get_precision' methods in IVTableData. (It's up to you to use precision in your GUI display. Keep in mind that unit-conversion will cause values like '1.0000001' if you don't do any string formatting.)

See warning above about .csv/.tsv editors. If you must use Excel or another 'smart' editor, then prefix all numbers with ' or _ to prevent modification!

Significant digits are counted from the left-most non-0 digit to the right-most digit if decimal is present, or to the right-most non-0 digit if decimal is not present, ignoring the exponential. Examples:

* '1e3' (1 significant digit)
* '1.000e3' (4 significant digits)
* '1000' (1 significant digit)
* '1100' (2 significant digits)
* '1000.' (4 significant digits)
* '1000.0' (5 significant digits)
* '1.0010' (5 significant digits)
* '0.0010' (2 significant digits)

Additionally, **any** number that is prefixed with '~' is considered a zero-precision value (0 significant digits). We use this in our Planetarium to display values such as '~1 km'.

## DB_ENTITIES_MOD Format

[Example Table](https://github.com/t2civ/astropolis_public/blob/master/data/tables/planets_mod.tsv)

Optional specifier: `@DB_ENTITIES_MOD[=<table_name>]` (table_name defaults to the base file name)  
Required directive: `@MODIFIES=<table_name>`  
Optional directive: `@DONT_PARSE`

This table modifies an existing DB_ENTITIES table. It can add entities or fields or overwrite existing data. There can be any number of DB_ENTITIES_MOD tables that modify a single DB_ENTITIES table. The importer assumes this format if the `@MODIFIES` directive is present.

Rules exactly follow DB_ENTITIES except that entity names _must_ be present and they _may or may not already exist_ in the DB_ENTITIES table being modified. If an entity name already exists, the mod table data will overwrite existing values. Otherwise, a new entity/row is added to the existing table. Similarly, field names may or may not already exist. If a new field/column is specified, then all previously existing entities (that are absent in the mod table) will be assigned the default value for this field.

## DB_ANONYMOUS_ROWS Format

Optional specifier: `@DB_ANONYMOUS_ROWS[=<table_name>]` (table_name defaults to the base file name)   
Optional directive: `@DONT_PARSE`

This table is exactly like DB_ENTITIES except that row names (the first column of each content row) are empty. The importer can identify this situation without the specifier directive. (Inconsistent use of row names will cause an import error assert.) This table will not create entity enumerations and does not have a 'name' field and cannot be modified by DB_ENTITIES_MOD, but is in other ways like DB_ENTITIES.

## ENUMERATION Format

[Example Table](https://github.com/t2civ/astropolis_public/blob/master/data/tables/major_strata.tsv)

Optional specifier: `@ENUMERATION[=<table_name>]` (table_name defaults to the base file name)  
Optional directive: `@DONT_PARSE`

This is a single-column 'enumeration'-only table. The importer assumes this format if the table has only one column. 

This is essentially a DB_ENTITIES format with only the 0-column: it creates entities enumerations with no data. There is no header row for field names and the only header tag that may be used (optionally) is `Prefix`. As for DB_ENTITIES, prefixing the 0-column is done by modifying the header tag as `Prefix/<entity prefix>`.

As for DB_ENTITIES, you can obtain row_number from the 'enumerations' dictionary (index with any entity name) or obtain an enum-like dictionary of entity names from the 'enumeration_dicts' dictionary (index with table_name or any entity_name).

## WIKI_LOOKUP Format

[Example Table](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/wiki_extras.tsv)

Required specifier: `@WIKI_LOOKUP[=<table_name>]` (table_name defaults to the base file name)  
Optional directive: `@DONT_PARSE`

This format can add items to the wiki lookup dictionary that were not added by DB_ENTITIES or DB_ENTITIES_MOD tables.

The format is the same as DB_ENTITIES except that fields can include only localization-prefixed '.wiki' (e.g., 'en.wiki'), and the only header tag allowed is `Prefix`. Prefix the 0-column by entering the header tag as `Prefix/<0-column prefix>`. The 0-column may contain any text and is **not** used to create entity enumerations.

For example usage, our [Planetarium](https://www.ivoyager.dev/planetarium/) uses this table format to create hyperlinks to Wikipedia.org pages for concepts such as 'Orbital_eccentricity' and 'Longitude_of_the_ascending_node' (i.e., non-entity items that don't exist in a DB_ENTITIES table). Alternatively, the lookup could be used for an internal game wiki.

## ENUM_X_ENUM Format

[Example Table](https://github.com/t2civ/astropolis_public/blob/master/data/tables/compositions_resources_percents.tsv)

Required specifier: `@ENUM_X_ENUM[=<table_name>]` (table_name defaults to the base file name)  
Required directive: `@DATA_TYPE=<Type>`  
Optional directives: `@DATA_DEFAULT=<Default>`, `@DATA_UNIT=<Unit>`, `@TRANSPOSE`, `@DONT_PARSE`

This format creates an array-of-arrays data structure where data is indexed [row_enumeration][column_enumeration] or the transpose if `@TRANSPOSE` is specified. All cells in the table have the same Type, Default and Unit (if applicable) specified by data directives above. If not specified, default 'nulls' for the six allowed Types are "", &"", false, NAN, -1 and [].

Enumerations must be 'known' by the plugin, which means that they were added as row entity names by a DB_ENTITIES, DB_ENTITIES_MOD or ENUMERATION format table, or were added as a 'project_enum' dictionary in the `postprocess_tables()` call.

The upper-left table cell can either be empty or specify row and column entity prefixes delimited by a backslash. E.g., 'RESOURCE_\FACILITY_' prefixes all row names with 'RESOURCE_' and all column names with 'FACILITY_'.

The resulting array-of-arrays structure will always have rows and columns that are sized and ordered according to the enumeration, not the table, if entities are missing or out of order in the table. Data not specified in the table file (omited row or column entities) will be imputed with default value.

