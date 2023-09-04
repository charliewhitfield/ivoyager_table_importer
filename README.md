# I, Voyager - Table Importer

TL;DR, it imports tables like [this](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv) and provides access to processed data that is statically typed, default-imputed, string-prefixed, unit-converted, and enumeration-to-integer-convered (using project- or table-defined enumerations), amongst other things. 

## Installation

The plugin directory `ivoyager_table_importer` should be added _directly to your addons directory_*. You can do this one of two ways:

1. Download and extract the plugin, then add it (in its entirety) to your addons directory, creating an 'addons' directory in your project if needed.
2. Add as a git submodule. From your project directory, use git command:  
    `git submodule add https://github.com/ivoyager/ivoyager_table_importer addons/ivoyager_table_importer`  
    This method will allow you to version-control the plugin using git rather than downloading, extracting and manually moving directories. You'll be able to checkout any plugin commit (from within your project) or submit pull requests back to us. This does require some learning to use git submodules. (We use [GitKraken](https://www.gitkraken.com/) to make this easier!)

(*Note: This differs from Godot doc's recomended plugin distribution, but allows us to version-control our plugins without manual directory operations.)

Then enable 'I, Voyager - Table Importer' from Godot Editor menu: Project / Project Settings / Plugins. The plugin will provide an autoload singleton called 'IVTableData' through which you can provide postprocessing intructions and interact with processed table data.

## Overview

This table importer & reader is maintained for [I, Voyager's](https://github.com/ivoyager) solar system simulator and associated apps and games. It's powerful but requires very specific file formatting. It's not meant to be a general 'read any' table utility.

It provides several specific table file formats that allow:
* Specification of data `Type` so that all table values are correctly converted to statically typed internal values.
* Specification of data `Default` to reduce table clutter. Fields that are mostly a particular value can be left mostly empty.
* Specification of data `Prefix` to reduce enumeration text size. E.g., shorten 'PLANET_MERCURY', 'PLANET_VENUS', 'PLANET_EARTH' to 'MERCURY', 'VENUS', 'EARTH'.
* Specification of float `Unit` so file data can be entered in the most convenient units while maintaining consistent internal representation.
* Table **enumerations** that may reference project enums _**or**_ table-defined entity names. For example, in our project, 'PLANET_EARTH' resolves to 3 as an integer _in any table_ because 'PLANET_EARTH' is row 3 in planets.tsv.
* 'Mod' tables that modify existing tables.
* [Optionally] Construction of a wiki lookup dictionary to use for an internal or external wiki.
* [For scientific apps, mostly] Determination of float significant digits from file text, so precision can be correctly displayed even after unit conversion.
* Easy or optimized access to _all_ processed and statically typed data via the IVTableData singleton.

File and table formats are described below.

## Usage

The plugin imports .tsv tables as a custom resource class. However, this class contains preprocessed data that isn't very useful except possibly for table debugging purposes.

Your only interface with the plugin should be with the autoload singleton **IVTableData**. From here you will give postprocessing instructions via function:

`postprocess_tables(table_names: Array, project_enums := [], unit_multipliers := {}, unit_lambdas := {}, enable_wiki := false, enable_precisions := false)`

Processed, statically typed data can then be accessed directly in IVTableData's dictionaries or via its many 'get' functions. IVTableData also provides functions to init dictionaries or objects directly from table data.

See IVTableData API in [table_data.gd](https://github.com/ivoyager/ivoyager_table_importer/blob/master/table_data.gd).

## General File Format and Table Editing

#### Delimiter and File Extension

We support only tab-delimited files with extension 'tsv'.

#### Table Directives

Any line starting with '@' is read as a table directive, which is used to specify one of several table formats and provide additional format-specific instructions. These can be at any line in the file. It may be convenient to include these at the end as many table viewers (including GitHub web pages) assume field names in the top line.

Table format is specified by one of `@DB_ENTITIES` (default), `@DB_ENTITIES_MOD`, `@ENUMERATION`, `@WIKI_LOOKUP`, or `@ENUM_X_ENUM`, optionally followed by the table name in the next cell to the right. If omitted, table name is taken from the base file name. Several table formats don't need a table format specifier as the parser can figure it out from the table itself. Some table formats allow or require additional specific directives. See below for format-specific directives.

To prevent any table from being parsed (for debugging or because it is under construction) use `@DONT_PARSE`. 

#### Comments

Any line starting with '#' is ignored. Additionally, entire columns are ignored if the column 'field' name begins with '#'.


#### Table Editor Warning!

Most .csv/.tsv file editors will 'interpret' and change your table data, especially any values that look like numbers or dates. For example, Excel will change '1.32712440018e20' to '1.33E+20' in your saved file without warning! One editor that does NOT change your data is [Rons Data Edit](https://www.ronsplace.ca/Products/RonsDataEdit). It's free for files with up to 1000 rows, or pay for 'pro' unlimited.

## DB_ENTITIES Format

[Example Table.](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv)

You can _optionally_ specify this table using `@DB_ENTITIES`. However, this is the default table format assumed if no table directives are present. No other file directives are allowed (except `@DONT_PARSE` which can always be used).

This format has database-style entities (as rows) and fields (as columns). Entities may or may not have names. If present, entity names are treated as enumerations, which are accessible in other tables (in any field with Type=INT) and must be globally unique.

Processed data are structured as a dictionary-of-statically-typed-field-arrays. Access the dictionary directly or use 'get' methods in IVTableData.

#### Header Rows

The first non-comment, non-directive line is assumed to hold the field names. The left-most cell must be empty.

After field names and before data, tables can have the following header rows in any order:
* `Type` (required) with column values:
   * `STRING` - Data processing applies Godot escaping such as \n, \t, etc. We also convert unicode '\u' escaping  up to \uFFFF (but not '\U' escaping for larger unicodes). Empty cells will be imputed with `Default` value or "".
   * `STRING_NAME` - No escaping. Empty cells will be imputed with `Default` value or &"".
   * `BOOL` - Case-insensitive 'True' or 'False'. 'x' (lower case) is interpreted as True. Empty cells will be imputed with `Default` value or False. Any other cell values will cause an error.
   * `INT` - A valid integer or text 'enumeration'. Enumerations may include any table entity name (from _any_ table) or hard-coded project enums specified in the `postprocess_tables()` call (enumerations that can't be found will cause an error at this function call). Empty cells will be imputed as `Default` or -1.
   * `FLOAT` - 'INF', '-INF' and 'NAN' (case-insensitive) are correctly interpreted. 'E' or 'e' are ok. Underscores '_' are allowed and removed before float conversion. '?' will be converted to INF. A '~' prefix is allowed and affects float precision (see below). Empty cells will be imputed with `Default` value or NAN. (See warning about .csv/.tsv editors above. If you must use Excel or another 'smart' editor, then prefix all numbers with ' or _ to prevent modification!)
   * `ARRAY[xxxx]` (where 'xxxx' specifies element type and is any of the above types) - The cell will be split by ',' (no space) and each element interpreted exactly as its type above. Column `Unit` and `Prefix`, if specified, are applied element-wise. Empty cells will be imputed with `Default` value or an empty but correctly typed array.
* `Default` (optional): Default values must be empty or follow Type rules above. If non-empty, this value is imputed for any empty cells in the column.
* `Unit` (optional; FLOAT fields only): The data processor recognizes a broad set of unit symbols (mostly but not all SI) and, by default, converts table floats to SI base units in the postprocessed 'internal' data. Default unit conversions are defined by 'unit_multipliers' and 'unit_lambdas' dictionaries [here](https://github.com/charliewhitfield/ivoyager_table_importer/blob/develop/table_unit_defaults.gd). Unit symbols and/or internal representation can be changed by specifying replacement conversion dictionaries in the `postprocess_tables()` call.
* `Prefix` (optional; STRING, STRING_NAME and INT fields only): Prefixes any non-empty cells with specified text. To prefix the column 0 implicit 'name' field, use `Prefix/<entity prefix>`. E.g., we use `Prefix/PLANET_` in [planets.tsv](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv) to prefix all entity names with 'PLANET_'.

#### Data Rows

* **Entity Name** (optional): The left-most 0-column is special. It can either specify an entity name or be empty, but entity name must be consistently present or absent for the entire table! If present, entity names are included in an implicit field called 'name' with Type=STRING_NAME. Prefix can be specified for the 0-column using header `Prefix/<entity prefix>`. Entity names (after prefixing) must be globally unique. They can be used in _any_ table as an enumeration that evaluates to the row number (INT) in the defining table. You can obtain row_number from the 'enumerations' dictionary (index with any entity name) or obtain an enum-like dictionary of entity names from the 'enumeration_dicts' dictionary (index with table_name or any entity_name).

All data cells have some processing on import before Type-processing described above:
* Double-quotes (") will be removed if they enclose the cell on both sides.
* A prefix single-quote (') will be removed.

#### Wiki

To create a wiki lookup dictionary, specify `enable_wiki = true` in the `postprocess_tables()` call. The postprocessor will populate the 'wiki_lookup' dictionary in IVTableData from any columns named 'en.wiki' in your table. (TODO: localization for 'fr.wiki', 'de.wiki', etc...)

For example usage, our [Planetarium](https://www.ivoyager.dev/planetarium/) uses this feature to create hyperlink text to Wikipedia.org pages for almost all table entities: e.g., 'Sun', 'Ceres_(dwarf_planet)', 'Hyperion_(moon)', etc. Alternatively, the lookup could be used for an internal game wiki.

#### Float Precision

For scientific or educational apps it is important to know and correctly represent data precision in GUI. To obtain a float value's original table precision in significant digits, specify `enable_precisions = true` in the `postprocess_tables()` call. You can then access float precisions via the 'precisions' dictionary or 'get_precision' methods in IVTableData. (It's up to you to use precision in your GUI display. Keep in mind that unit-conversion will cause values like '1.0000001' if you don't do any string formatting.)

Example precision from table cell text:

* '1e3' (1 significant digit)
* '1.000e3' (4 significant digits)
* '1000' (1 significant digit)
* '1100' (2 significant digits)
* '1000.' (4 significant digits)
* '1000.0' (5 significant digits)
* '1.0010' (5 significant digits)
* '0.0010' (2 significant digits)
* **Any** number prefixed with '~' (0 significant digits). We use this in our Planetarium to display values such as '~1 km'.

## DB_ENTITIES_MOD Format

(Example coming soon!)

This table modifies an existing DB_ENTITIES table. It can add entities or fields or overwrite existing data.

You can _optionally_ specify this table using `@DB_ENTITIES_MOD`. However, this format requires the `@MODIFIES` directive and the parser will read the table as DB_ENTITIES_MOD format if `@MODIFIES` is present. The `@MODIFIES` directive must be followed (after tab delimiter) by the name of the table to be modified (use table name, not file name: e.g., 'planets' not 'planets.tsv').

Rules exactly follow DB_ENTITIES except that entity names _must_ be present and they _may or may not already exist_ in the DB_ENTITIES table being modified. If an entity name already exists, the mod table data will overwrite existing values. Otherwise, a new entity/row is added to the existing table. Similarly, field names may or may not already exist. If a new field/column is specified, then all previously existing entities (that are absent in the mod table) will be assigned the default value for this field.

## ENUMERATION Format

(Example coming soon!)

This is a single-column 'enumeration'-only table.

The format can be _optionally_ specified using `@ENUMERATION`. This is optional because the importer will attempt to read any single-column table as an ENUMERATION format.

This is essentially a DB_ENTITIES format with only the 0-column: it creates entities enumerations with no data. There is no header row for field names and the only header tag that may be used (optionally) is `Prefix`. As for DB_ENTITIES, prefixing the 0-column is done by modifying the header tag as `Prefix/<entity prefix>`.

As for DB_ENTITIES, you can obtain row_number from the 'enumerations' dictionary (index with any entity name) or obtain an enum-like dictionary of entity names from the 'enumeration_dicts' dictionary (index with table_name or any entity_name).

## WIKI_LOOKUP Format

[Example Table.](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/wiki_extras.tsv)

This format can add items to the wiki lookup dictionary that were not added by DB_ENTITIES tables.

This format _must_ be specified using `@WIKI_LOOKUP`.

The format is the same as DB_ENTITIES except that fields can include only 'en.wiki', 'fr.wiki', etc., and the only header tag allowed is `Prefix`. Prefix the 0-column by entering the header tag as `Prefix/<0-column prefix>`. The 0-column may contain any text and is **not** used to create entity enumerations.

For example usage, our [Planetarium](https://www.ivoyager.dev/planetarium/) uses this table format to create hyperlinks to Wikipedia.org pages for concepts such as 'Orbital_eccentricity' and 'Longitude_of_the_ascending_node' (i.e., non-entity items that don't exist in a DB_ENTITIES table). Alternatively, the lookup could be used for an internal game wiki.

## ENUM_X_ENUM Format

[Example Table.](https://github.com/t2civ/astropolis_public/blob/main/data/tables/compositions_resources_percents.tsv)

This format creates an array-of-arrays data structure where indexes are defined by a column enumeration and a row enumeration. All cells in the table have the same Type, Default and (for floats) Unit.

This format _must_ be specified using `@ENUM_X_ENUM`. Specify Type, Default and Unit using `@TABLE_TYPE` (required), `@TABLE_DEFAULT` (optional) and `@TABLE_UNIT` (optional; FLOAT only). 


WIP
