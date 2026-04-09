defmodule ExUnitBuildkite.FormatterTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, _} = ExUnitBuildkite.TestAnnotator.start_link()
    Application.put_env(:exunit_buildkite, :annotator, ExUnitBuildkite.TestAnnotator)

    on_exit(fn ->
      Application.delete_env(:exunit_buildkite, :annotator)

      if Process.whereis(ExUnitBuildkite.TestAnnotator) do
        Agent.stop(ExUnitBuildkite.TestAnnotator)
      end
    end)
  end

  describe "format_annotation/3" do
    test "includes test name and location" do
      test = failed_test()
      html = ExUnitBuildkite.Formatter.format_annotation(test, failures(test), 1)

      assert html =~ "something fails"
      assert html =~ "test/some_test.exs:42"
      assert html =~ "<details>"
      assert html =~ "<pre>"
    end

    test "includes module name" do
      test = failed_test(module: ExUnitBuildkite.FakeTest)
      html = ExUnitBuildkite.Formatter.format_annotation(test, failures(test), 1)

      assert html =~ "ExUnitBuildkite.FakeTest"
    end

    test "includes assertion details" do
      test = failed_test()
      html = ExUnitBuildkite.Formatter.format_annotation(test, failures(test), 1)

      assert html =~ "Assertion with == failed"
    end

    test "escapes HTML in test output" do
      test = failed_test(name: :"test <script>alert</script>")
      html = ExUnitBuildkite.Formatter.format_annotation(test, failures(test), 1)

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "strips 'test ' prefix from name in summary" do
      test = failed_test(name: :"test my feature works")
      html = ExUnitBuildkite.Formatter.format_annotation(test, failures(test), 1)

      assert html =~ "<code>my feature works</code>"
    end
  end

  describe "formatter GenServer" do
    test "annotates on test failure" do
      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:test_finished, failed_test()})
      _ = :sys.get_state(formatter)

      annotations = ExUnitBuildkite.TestAnnotator.annotations()
      assert length(annotations) == 1

      [{body, context, style}] = annotations
      assert context == "exunit"
      assert style == "error"
      assert body =~ "something fails"
    end

    test "ignores passing tests" do
      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:test_finished, passing_test()})
      _ = :sys.get_state(formatter)

      assert ExUnitBuildkite.TestAnnotator.annotations() == []
    end

    test "ignores skipped tests" do
      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:test_finished, skipped_test()})
      _ = :sys.get_state(formatter)

      assert ExUnitBuildkite.TestAnnotator.annotations() == []
    end

    test "tracks failure count across multiple failures" do
      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:test_finished, failed_test(name: :"test first")})
      GenServer.cast(formatter, {:test_finished, failed_test(name: :"test second")})
      _ = :sys.get_state(formatter)

      annotations = ExUnitBuildkite.TestAnnotator.annotations()
      assert length(annotations) == 2
    end

    test "ignores unrelated events" do
      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:suite_started, %{}})
      GenServer.cast(formatter, {:module_started, %ExUnit.TestModule{name: Foo, state: nil, tests: []}})
      _ = :sys.get_state(formatter)

      assert ExUnitBuildkite.TestAnnotator.annotations() == []
    end

    test "respects custom context and style" do
      {:ok, formatter} =
        GenServer.start_link(ExUnitBuildkite.Formatter, context: "backend", style: "warning")

      GenServer.cast(formatter, {:test_finished, failed_test()})
      _ = :sys.get_state(formatter)

      [{_body, context, style}] = ExUnitBuildkite.TestAnnotator.annotations()
      assert context == "backend"
      assert style == "warning"
    end

    test "respects application config" do
      Application.put_env(:exunit_buildkite, :context, "app-tests")
      Application.put_env(:exunit_buildkite, :style, "info")

      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, [])

      GenServer.cast(formatter, {:test_finished, failed_test()})
      _ = :sys.get_state(formatter)

      [{_body, context, style}] = ExUnitBuildkite.TestAnnotator.annotations()
      assert context == "app-tests"
      assert style == "info"
    after
      Application.delete_env(:exunit_buildkite, :context)
      Application.delete_env(:exunit_buildkite, :style)
    end

    test "inline opts take precedence over application config" do
      Application.put_env(:exunit_buildkite, :context, "from-config")

      {:ok, formatter} = GenServer.start_link(ExUnitBuildkite.Formatter, context: "from-opts")

      GenServer.cast(formatter, {:test_finished, failed_test()})
      _ = :sys.get_state(formatter)

      [{_body, context, _style}] = ExUnitBuildkite.TestAnnotator.annotations()
      assert context == "from-opts"
    after
      Application.delete_env(:exunit_buildkite, :context)
    end
  end

  # -- Test Helpers --------------------------------------------------------

  defp failed_test(opts \\ []) do
    name = Keyword.get(opts, :name, :"test something fails")
    module = Keyword.get(opts, :module, Some.Test)
    file = Keyword.get(opts, :file, "test/some_test.exs")
    line = Keyword.get(opts, :line, 42)

    %ExUnit.Test{
      name: name,
      module: module,
      state:
        {:failed,
         [
           {:error,
            %ExUnit.AssertionError{
              expr: {:==, [], [1, 2]},
              left: 1,
              right: 2,
              message: "Assertion with == failed"
            }, [{module, name, 1, [file: String.to_charlist(file), line: line]}]}
         ]},
      tags: %{file: file, line: line},
      time: 1234,
      logs: ""
    }
  end

  defp passing_test do
    %ExUnit.Test{
      name: :"test something passes",
      module: Some.Test,
      state: nil,
      tags: %{file: "test/some_test.exs", line: 10},
      time: 500,
      logs: ""
    }
  end

  defp skipped_test do
    %ExUnit.Test{
      name: :"test something skipped",
      module: Some.Test,
      state: {:skipped, "reason"},
      tags: %{file: "test/some_test.exs", line: 20},
      time: 0,
      logs: ""
    }
  end

  defp failures(%ExUnit.Test{state: {:failed, failures}}), do: failures
end
