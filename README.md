# IVoyager Table Importer

**_This is a Work-in-Progress addon. The functionality currently exists in I, Voyager's core submodule 'ivoyager', but the plan is to separate it out as a Godot Editor plugin. See proposal [here](https://github.com/orgs/ivoyager/discussions/11)._**

**_WIP readme for the plugin follows..._**

This table importer & reader is maintained for [I, Voyager's](https://github.com/ivoyager) solar system simulator and associated apps and games. See example tables [here](https://github.com/ivoyager/ivoyager/tree/master/data/solar_system).

It provides several specific table file formats that allow:
* Specification of data `Type` so that all table values are correctly converted to statically typed internal values.
* Specification of data `Default` to reduce table clutter. Fields that are moslty a particular value can be left mostly blank.
* Specification of data `Prefix` to reduce enumeration text size. E.g., shorten 'PLANET_MERCURY', 'PLANET_VENUS', 'PLANET_EARTH', ..., to 'MERCURY', 'VENUS', 'EARTH', ....
* Specification of float `Unit` so file data can be entered in the most convenient units while maintaining consistent internal representation.
* Enumerations that may reference project enums **OR** table-defined entities. For example, in our project, 'PLANET_EARTH' resolves to 3 as an INT _**in any table**_ because 'PLANET_EARTH' is row 3 in planets.tsv.
* Easy access to processed data via the IVTableData singleton. Typed data can be obtained directly from data structures (e.g., dictionaries-of-field-arrays) or by using 'get' methods. Additional methods provide for dictionary or object contsruction from table data.
* [Optionally] Construction of a wiki lookup table for all or specific table row entities. E.g., Wikipedia.org titles or keys to an internal wiki.
* [For scientific apps, mostly] Determination of float significant digits from file text, so precision can be correctly displayed even after unit conversion.

File and table formats are described below.

**Table Editor Warning!** Most .csv/.tsv file editors will "interpret" and modify cell values. For example, Excel will change "1.32712440018e20" to "1.33E+20" in your saved file without warning, and it's very hard to stop it from doing so! One editor that does NOT change your data is [Rons Data Edit](https://www.ronsplace.ca/Products/RonsDataEdit). It's free for files with up to 1000 rows, or pay for "pro" unlimited.

## General File Format

We currently support only tab-delimited files with extension *.tsv. (Rons Data Edit can convert for you without data corruption.)

#### Table Directives

Any line starting with '@' is read as a table directive, which is used to specify one of several table formats and provide additional format-specific instructions. These can be at any line in the file. (It's convenient to include these at the end as many table viewers, including GitHub, assume field names in the top line.)

Table format is specified by one of: `@DB_ENTITIES` (default), `@DB_ENTITIES_MOD`, `@ENUMERATION`, `@WIKI_TITLES`, or `@ENUM_X_ENUM`. Some table formats allow or require additional specific directives (see formats below).

#### Comments

Any line starting with '#' is ignored. Additionally, entire columns are ignored if the column 'field' name begins with '#'.

## DB_ENTITIES Format

This is the default table format, assumed if no table directives are present. It is a database-style entities (rows) by fields (columns) table. Entities may or may not have names. If present, entity names are treated as enumerations, which are accessible in other tables and must be globally unique. See example table [here](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv).

Processed data are structured as a dictionary of statically typed field arrays. Field names define the dictionary keys and entity names (resolved as enumeration integers) define the array indexes. The dictionary can be accessed directly or by using 'get' methods in the IVTableData singleton.

No other file directives are allowed, as the file format specifies everything we need in its header. 

#### Header Rows

The first non-comment, non-directive line is assumed to hold the field names. The left-most cell must be empty.

After field names and before data, tables can have the following header rows in any order:
* `Type` (required) with column values:
   * `STRING` - Data processing applies Godot escaping such as \n, \t, \uXXXX, etc. Blank cells will be imputed with `Default` value or "".
   * `STRING_NAME` - No escaping. Blank cells will be imputed with `Default` value or &"".
   * `BOOL` - Case-insensitive "True" or "False". "x" (lower case) is interpreted as True. Blank cells will be imputed with `Default` value or False. Any other cell values will cause an error.
   * `INT` - A valid integer or text "enumeration". Enumerations may include any table entity name (from _any_ table) or hard-coded enums specified by calling IVTableData.add_enum(enum_dictionary). Enumerations that can't be found will throw a warning and be imputed as -1. Blank cells will be imputed as `Default` or -1.
   * `FLOAT` - See WARNING about Excel above; if you must use it, then prefix all numbers with ' or _ to prevent modification. "E" or "e" are ok. "?" will be converted to INF. A "~" prefix is allowed and affects float precision (see below). Blank cells will be imputed with `Default` value or NAN.
   * `ARRAY[xxxx]` (where 'xxxx' specifies element type and is any of the above types) - The cell will be split by ',' (no space) and each element interpreted exactly as its type above. Column `Unit` and `Prefix`, if specified, are applied element-wise. Blank cells will be imputed with `Default` value or an empty (but correctly typed) array.
* `Default` (optional): Default values must be blank or follow Type rules above. If non-blank, this value is imputed for any blank cells in the column.
* `Unit` (optional; FLOAT fields only): The data processor recognizes a broad set of unit symbols (mostly but not all SI) and, by default, convertes the table value to [SI base units](https://en.wikipedia.org/wiki/International_System_of_Units) internally. Unit symbols can be added or internal representation changed by modifying or replacing dictionary 'unit_multipliers' or 'unit_lambdas' (the latter handles oddities like °C, °F or dB).
* `Prefix` (optional; STRING, STRING_NAME and INT fields only): Prefixes any non-blank cells with specified text. To prefix the column 0 implicit 'name' field, use `Prefix/<value>`. E.g., `Prefix/PLANET_` is used in our [planets.tsv](https://github.com/ivoyager/ivoyager/blob/master/data/solar_system/planets.tsv) to prefix all row names with 'PLANET_'.

#### Data Rows

* **Entity Name (optional).** The left-most 0-column is special. It can either specify an entity name or be blank, but entity name must be consistently present or absent for the entire table. If present, entity names are included in an implicit field called 'name' with Type=STRING_NAME. Prefix can be specified for the 0-column using header `Prefix/<value>`. Entity names (after prefixing) must be globally unique. They can be used in _any_ table as an enumeration that evaluates to the row number (INT) in the defining table. You can get the row number using `IVTableData.enumerations[<row name>]` or obtain an enum-like dictionary for a table's entity names using `IVTableData.get_row_name_dictionary(<table name>)`.

All data cells have some processing on import and may have further post-processing:
* Double-quotes (") will be removed if they enclose the cell on both ends.
* A prefix single-quote (') or underscore (_) will be removed.
* Further processing is by `Type` as described above; the processed table value will be statically typed.

#### Float Precision

For scientific apps (maybe not so much for games) it is useful to know and correctly represent data precision in GUI. To obtain a float value's original table precision in siginificant digits, set `IVTableData.keep_precision = true` and access via `IVTableData.precisions` dictionary or specific 'get_precision' methods.

Example precision from table cell text (note again that Excel will ruin these!):
* '1e3' (1 significant digit)
* '1000' (1 significant digit)
* '1100' (2 significant digits)
* '1.000e3' (4 significant digits)
* '1000.' (4 significant digits)
* '1000.0' (5 significant digits)
* '1.0010' (5 significant digits)
* '0.0010' (2 significant digits)
* Any number prefixed with '~' will be interpreted as a 'zero-precision' number (0 significant digits). Our Planetarium displays these as, for example, '~1 km'.

#### Internal Representation and Data Access

Processed data for each table is held in a dictionary-of-field-arrays structure. Each field-array is statically typed as specified by field Type. The table dictionary can be obtained by `IVTableData.tables[<table name>]`. 

## DB_ENTITIES_MOD Format

This table modifies an existing DB_ENTITIES table. It can add entities or fields, or overwrite existing data.

Rules exactly follow rules for DB_ENTITIES except that entity names may or may not already exist. If an entity name already exists, the mod table data will overwrite existing values. Otherwise, a new entity/row is added to the existing table. Similarly, field names may or may not already exist. If a new field/column is specified, then all previously existing entities (that are absent in the mod table) will be assigned the default value for this field.

## ENUMERATION Format

Specifies a single-column 'enumeration' table. No other file directives can be present.

You can obtain row_number using IVTableData.enumerations[entity_name]. Or you can obtain an enum-like dictionary structure using IVTableData.get_enumeration(table_name).

## WIKI_TITLES Format

Columns 'en.wiki', etc., provide localized translation of text keys into wiki title keys for external or internal wiki access. No other file directives can be present.

## ENUM_X_ENUM Format

WIP - CW uses this format for game dev and is bringing it into core I, Voyager. See example table [here](https://github.com/t2civ/astropolis_public/blob/main/data/tables/compositions_resources_percents.tsv).
