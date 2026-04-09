defmodule ExUnitBuildkite.Formatter do
  @moduledoc """
  An ExUnit formatter that annotates Buildkite builds with test failures in real-time.

  Each test failure is immediately sent to `buildkite-agent annotate --append`,
  appearing in the build's annotation panel as it happens.

  The formatter is safe to use outside Buildkite — if `buildkite-agent` is not
  found, failures are silently skipped.
  """

  use GenServer

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
  test name, location, and formatted failure output.

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
        case System.cmd(path, ["annotate", body, "--append", "--style", style, "--context", context],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {output, code} -> {:error, "exit #{code}: #{output}"}
        end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

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
