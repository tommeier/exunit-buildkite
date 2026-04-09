# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-04-09

### Changed

- Comprehensive README with migration guide, monorepo examples, and comparison table
- Detailed moduledocs on `ExUnitBuildkite` and `ExUnitBuildkite.Formatter` with configuration reference
- Added Hexdocs badge and Changelog link to Hex package metadata

## [0.1.0] - 2026-04-09

### Added

- `ExUnitBuildkite.Formatter` — ExUnit formatter that annotates Buildkite builds with
  test failures in real-time via `buildkite-agent annotate --append`
- Configurable annotation context and style (via application env or inline opts)
- Safe no-op when `buildkite-agent` is not available (local dev, other CI)
- HTML `<details>` blocks with test name, module, file:line, and formatted failure output

[0.2.0]: https://github.com/tommeier/exunit-buildkite/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tommeier/exunit-buildkite/releases/tag/v0.1.0
