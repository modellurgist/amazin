defmodule Amazin.Interceptor do
  @moduledoc """
  Data-driven interceptor pipeline for event processing.

  V20 variant: each event has a declared pipeline of interceptor modules.
  Interceptors run in two phases:

  - **Enter** (left → right): inject data, dispatch to machines, pre-process
  - **Leave** (right → left): route signals, post-process, clean up

  Pipelines are declared as data (lists of modules), making them
  inspectable, composable, and trivially extensible.

  Inspired by re-frame (Clojure) and Pedestal interceptor chains.
  """

  defmodule Context do
    @moduledoc "Immutable data bag flowing through the interceptor pipeline."
    defstruct [:event, :data, :domain, :ui, outcomes: []]

    @type t :: %__MODULE__{
            event: atom(),
            data: map(),
            domain: struct(),
            ui: struct(),
            outcomes: [term()]
          }
  end

  @callback enter(Context.t()) :: Context.t()
  @callback leave(Context.t()) :: Context.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Amazin.Interceptor
      alias Amazin.Interceptor.Context
      import Amazin.Outcome

      @impl true
      def enter(ctx), do: ctx

      @impl true
      def leave(ctx), do: ctx

      defoverridable enter: 1, leave: 1
    end
  end

  @spec execute([module()], Context.t()) :: Context.t()
  def execute(interceptors, %Context{} = ctx) do
    entered = Enum.reduce(interceptors, ctx, fn mod, c -> mod.enter(c) end)
    Enum.reduce(Enum.reverse(interceptors), entered, fn mod, c -> mod.leave(c) end)
  end
end
