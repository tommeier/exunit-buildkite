defmodule ExUnitBuildkite do
  @moduledoc """
  Real-time Buildkite annotations for ExUnit test failures.

  ExUnitBuildkite is an ExUnit formatter that calls `buildkite-agent annotate`
  as each test failure occurs, giving you immediate visibility into what's
  broken — no separate pipeline step required.

  ## Usage

  Add the formatter to your `test/test_helper.exs`:

      formatters =
        if System.get_env("CI") do
          [ExUnitBuildkite.Formatter, ExUnit.CLIFormatter]
        else
          [ExUnit.CLIFormatter]
        end

      ExUnit.start(formatters: formatters)

  ## Configuration

  Configuration is optional. Defaults work out of the box.

      # config/test.exs
      config :exunit_buildkite,
        context: "exunit",    # annotation context (groups annotations together)
        style: "error"        # annotation style: "error", "warning", "info", "success"

  You can also pass options directly to the formatter:

      ExUnit.start(formatters: [
        {ExUnitBuildkite.Formatter, context: "backend-tests"},
        ExUnit.CLIFormatter
      ])

  Inline options take precedence over application config.
  """
end
