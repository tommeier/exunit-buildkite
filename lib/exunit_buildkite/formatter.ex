defmodule ExUnitBuildkite.Formatter do
  @moduledoc """
  An ExUnit formatter that annotates Buildkite builds with test failures in real-time.

  This module implements the ExUnit formatter protocol — a `GenServer` that receives
  test lifecycle events. On each test failure, it formats the failure output and sends
  it to `buildkite-agent annotate --append`, which adds it to the build's annotation
  panel in the Buildkite UI.

  ## Formatter Protocol

  ExUnit sends the following events via `GenServer.cast/2`:

  | Event | Handled? | Description |
  |-------|----------|-------------|
  | `{:test_finished, %ExUnit.Test{state: {:failed, _}}}` | Yes | Formats and annotates the failure |
  | `{:test_finished, %ExUnit.Test{state: nil}}` | No | Passing test — ignored |
  | `{:suite_started, _}` | No | Ignored |
  | `{:suite_finished, _}` | No | Ignored |
  | `{:module_started, _}` | No | Ignored |
  | `{:module_finished, _}` | No | Ignored |

  ## Annotation Output

  Each failure produces a collapsible HTML block:

  ```html
  <details>
    <summary>
      <code>test name</code> — Module (<code>file:line</code>)
    </summary>
    <pre>formatted failure output from ExUnit</pre>
  </details>
  ```

  Multiple failures are appended to the same annotation context, producing a
  stacked list of collapsible failure blocks.

  ## Custom Annotator

  For testing or custom integrations, you can replace the built-in annotator
  (which calls `buildkite-agent`) with your own module:

      config :exunit_buildkite, annotator: MyApp.TestAnnotator

  The module must implement `annotate/3`:

      @callback annotate(body :: String.t(), context :: String.t(), style :: String.t()) :: :ok
  """

  use GenServer

  @typedoc "Formatter state tracked across test events."
  @type state :: %{
          context: String.t(),
          style: String.t(),
          failure_count: non_neg_integer()
        }

  # -- Client API ----------------------------------------------------------

  @doc false
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    {:ok,
     %{
       context: get_config(opts, :context, "exunit"),
       style: get_config(opts, :style, "error"),
       failure_count: 0
     }}
  end

  # -- Formatter Events ----------------------------------------------------

  @doc false
  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, failures}} = test}, state) do
    counter = state.failure_count + 1
    html = format_annotation(test, failures, counter)
    annotate(html, state)
    {:noreply, %{state | failure_count: counter}}
  end

  def handle_cast(_event, state) do
    {:noreply, state}
  end

  # -- Formatting ----------------------------------------------------------

  @doc """
  Formats a test failure as an HTML annotation for Buildkite.

  Returns an HTML string containing a collapsible `<details>` block with the
  test name, module, file location, and the full formatted failure output
  from `ExUnit.Formatter.format_test_failure/5`.

  This function is public to support direct testing of annotation output.

  ## Parameters

    * `test` — the `%ExUnit.Test{}` struct for the failed test
    * `failures` — the failures list from `test.state` (list of `{kind, reason, stack}` tuples)
    * `counter` — failure number (used for numbering in the formatted output)

  ## Examples

      iex> test = %ExUnit.Test{
      ...>   name: :"test addition",
      ...>   module: MyApp.MathTest,
      ...>   state: {:failed, [{:error, %ExUnit.AssertionError{
      ...>     expr: {:==, [], [1, 2]},
      ...>     message: "Assertion with == failed"
      ...>   }, []}]},
      ...>   tags: %{file: "test/math_test.exs", line: 5},
      ...>   time: 100, logs: ""
      ...> }
      iex> html = ExUnitBuildkite.Formatter.format_annotation(test, elem(test.state, 1), 1)
      iex> html =~ "test addition"
      true
      iex> html =~ "test/math_test.exs:5"
      true
      iex> html =~ "<details>"
      true
  """
  @spec format_annotation(ExUnit.Test.t(), list(), pos_integer()) :: String.t()
  def format_annotation(%ExUnit.Test{} = test, failures, counter) do
    formatted =
      test
      |> ExUnit.Formatter.format_test_failure(failures, counter, :infinity, &text_formatter/2)
      |> IO.iodata_to_binary()
      |> String.trim()

    test_name = to_string(test.name) |> String.replace_prefix("test ", "")
    file = Map.get(test.tags, :file, "unknown")
    line = Map.get(test.tags, :line, 0)

    """
    <details>
    <summary><code>#{escape_html(test_name)}</code> — #{escape_html(inspect(test.module))} \
    (<code>#{escape_html(file)}:#{line}</code>)</summary>
    <pre>#{escape_html(formatted)}</pre>
    </details>
    """
  end

  # -- Private -------------------------------------------------------------

  defp get_config(opts, key, default) do
    Keyword.get(opts, key, Application.get_env(:exunit_buildkite, key, default))
  end

  defp annotate(html, state) do
    annotator = Application.get_env(:exunit_buildkite, :annotator)

    result =
      if annotator do
        annotator.annotate(html, state.context, state.style)
      else
        cli_annotate(html, state.context, state.style)
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        IO.warn("[ExUnitBuildkite] Failed to annotate: #{inspect(reason)}")
        :ok
    end
  end

  defp cli_annotate(body, context, style) do
    case System.find_executable("buildkite-agent") do
      nil ->
        {:error, :buildkite_agent_not_found}

      path ->
        case System.cmd(
               path,
               ["annotate", body, "--append", "--style", style, "--context", context],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {output, code} -> {:error, "exit #{code}: #{output}"}
        end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Plain text formatter for ExUnit.Formatter.format_test_failure/5.
  # Returns diff-enabled output without ANSI color codes.
  defp text_formatter(:diff_enabled?, _), do: true
  defp text_formatter(_, msg), do: msg

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
