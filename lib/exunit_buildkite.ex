defmodule ExUnitBuildkite do
  @moduledoc """
  Real-time Buildkite build annotations for ExUnit test failures.

  ExUnitBuildkite is an ExUnit formatter that calls `buildkite-agent annotate`
  as each test failure occurs, giving you immediate visibility into what's
  broken — no separate pipeline step required.

  ## Quick Start

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

  You can also pass options directly to the formatter — inline options take
  precedence over application config:

      ExUnit.start(formatters: [
        {ExUnitBuildkite.Formatter, context: "backend-tests"},
        ExUnit.CLIFormatter
      ])

  ## Configuration Options

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `:context` | `String.t()` | `"exunit"` | Buildkite annotation context. Annotations sharing a context are grouped into a single block. |
  | `:style` | `String.t()` | `"error"` | Annotation style: `"error"`, `"warning"`, `"info"`, or `"success"`. |
  | `:annotator` | `module()` | *(built-in)* | Override the module that sends annotations. Must implement `annotate/3`. Used for testing. |

  ## How It Works

  The formatter is a `GenServer` that receives ExUnit events via `handle_cast/2`.
  When a test finishes with `state: {:failed, failures}`, it:

  1. Formats the failure using `ExUnit.Formatter.format_test_failure/5`
  2. Wraps the output in a collapsible HTML `<details>` block
  3. Calls `buildkite-agent annotate --append` to send it to the build

  The formatter runs in its own process and never blocks test execution. If
  `buildkite-agent` is not available (local dev, other CI), annotation calls
  silently fail with a warning — tests are never affected.

  ## Monorepo Usage

  In monorepos with multiple test suites, use the `:context` option to keep
  annotations separate per app:

      # apps/api/test/test_helper.exs
      {ExUnitBuildkite.Formatter, context: "api-tests"}

      # apps/worker/test/test_helper.exs
      {ExUnitBuildkite.Formatter, context: "worker-tests"}
  """
end
