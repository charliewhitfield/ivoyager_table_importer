# Changelog

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v0.0.6] - 2023-10-05

Developed using Godot 4.1.2.

### Added

* Translation file for large number and unit names in IVQFormat.

### Changed

* Removed dictionary keys for some peculiar compound units used in astronomy. (The parser can still process these.)

## [v0.0.7] - Not Released

Under development using Godot 4.2.dev6 (backward breaking changes!)

### Changed
* For loop typing and error fixes for Godot 4.2.

## [v0.0.6] - 2023-10-05

Developed using Godot 4.1.1.

### Fixed
* Added text translation file for large numbers and long-form units.

## [v0.0.5] - 2023-10-03

Developed using Godot 4.1.1.

### Added

* Autoload singletons IVQFormat, IVUnits and IVQConvert (the latter two replace static classes).
* table_importer.cfg

### Changed
* Editor plugin now uses a config file (with optional project level override config) to define all autoloads. This is mainly so the user can reasign IVUnits.
* Restructured directories.

## [v0.0.4] - 2023-09-25

Developed using Godot 4.1.1.

### Added
* A compound unit string parser! It can parse compound units like 'm^3/(kg s^2)'.
* @DB_ANONYMOUS_ROWS table format.

### Changed
* More and more informative asserts for table problems and function misuse.
* [Breaks API] Renamed several IVTableData functions.

## [v0.0.3] - 2023-09-06

Developed using Godot 4.1.1.

### Changed
* Removed @tool from files that are not part of the resource import.
* [Breaks API] Renamed many API functions with `_db_` to make it clear what tables are valid input.

## [v0.0.2] - 2023-09-05

Developed using Godot 4.1.1.

### Changed
* Improved table asserts with row, column and/or field position
* [Breaking] Table directive format is now @XXXX=xxxx (in one table cell).

## v0.0.1 - 2023-09-04

Developed using Godot 4.1.1.

Initial alpha release!


[v0.0.7]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.6...HEAD
[v0.0.6]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.5...v0.0.6
[v0.0.5]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.4...v0.0.5
[v0.0.4]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.3...v0.0.4
[v0.0.3]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.2...v0.0.3
[v0.0.2]: https://github.com/ivoyager/ivoyager_table_importer/compare/v0.0.1...v0.0.2
