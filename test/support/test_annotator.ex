defmodule ExUnitBuildkite.TestAnnotator do
  @moduledoc false
  use Agent

  def start_link do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def annotate(body, context, style) do
    Agent.update(__MODULE__, &[{body, context, style} | &1])
    :ok
  end

  def annotations do
    Agent.get(__MODULE__, &Enum.reverse/1)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
end
