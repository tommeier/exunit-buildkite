# ExUnitBuildkite

[![Hex.pm](https://img.shields.io/hexpm/v/exunit_buildkite.svg)](https://hex.pm/packages/exunit_buildkite)
[![CI](https://github.com/tommeier/exunit-buildkite/actions/workflows/ci.yml/badge.svg)](https://github.com/tommeier/exunit-buildkite/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/exunit_buildkite.svg)](LICENSE)

Real-time Buildkite annotations for ExUnit test failures. The Elixir equivalent of
[rspec-buildkite](https://github.com/buildkite/rspec-buildkite).

Each test failure is immediately annotated on the Buildkite build as it occurs — no
separate pipeline step, no JUnit XML, no post-processing.

## Installation

Add `exunit_buildkite` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exunit_buildkite, "~> 0.1", only: :test}
  ]
end
```

## Usage

Add the formatter to your `test/test_helper.exs`, alongside `ExUnit.CLIFormatter`:

```elixir
formatters =
  if System.get_env("CI") do
    [ExUnitBuildkite.Formatter, ExUnit.CLIFormatter]
  else
    [ExUnit.CLIFormatter]
  end

ExUnit.start(formatters: formatters)
```

That's it. Test failures will appear as Buildkite annotations in real-time.

The formatter is safe to use outside Buildkite — if `buildkite-agent` is not available,
it silently does nothing.

## Configuration

Defaults work out of the box. Optionally configure via application env:

```elixir
# config/test.exs
config :exunit_buildkite,
  context: "exunit",    # annotation context (groups annotations together)
  style: "error"        # annotation style: "error", "warning", "info", "success"
```

Or pass options inline:

```elixir
ExUnit.start(formatters: [
  {ExUnitBuildkite.Formatter, context: "backend-tests", style: "error"},
  ExUnit.CLIFormatter
])
```

Inline options take precedence over application config.

## How It Works

`ExUnitBuildkite.Formatter` is a GenServer that receives ExUnit events. On each test
failure, it:

1. Formats the failure using `ExUnit.Formatter.format_test_failure/5` (same output you
   see in the terminal)
2. Wraps it in a collapsible HTML `<details>` block with the test name and file location
3. Calls `buildkite-agent annotate --append` to add it to the build's annotation panel

Failures appear immediately — while subsequent tests are still running.

## Replacing junit-annotate

If you're currently using `junit_formatter` + the `junit-annotate` Buildkite plugin as
a separate pipeline step, you can replace both with this single formatter:

1. Remove `junit_formatter` from your deps and config
2. Remove the JUnit annotation step from your pipeline
3. Remove the JUnit XML upload from your test script
4. Add `ExUnitBuildkite.Formatter` to your `test_helper.exs`

## License

MIT — see [LICENSE](LICENSE).
