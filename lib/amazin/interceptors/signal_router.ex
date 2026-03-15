defmodule Amazin.Interceptors.SignalRouter do
  @moduledoc """
  Leave-phase interceptor: extracts `{:signal, name}` tuples from outcomes
  and routes each to `CartUI.react/2`, collecting any reactive outcomes.

  After this interceptor runs, no `{:signal, _}` tuples remain in outcomes.
  """
  use Amazin.Interceptor
  alias Amazin.UI.CartUI

  @impl true
  def leave(ctx) do
    {signals, effects} = Enum.split_with(ctx.outcomes, &match?({:signal, _}, &1))

    {ui, react_outcomes} =
      Enum.reduce(signals, {ctx.ui, []}, fn {:signal, name}, {ui, acc} ->
        {new_ui, new_outcomes} = CartUI.react(name, ui)
        {new_ui, acc ++ new_outcomes}
      end)

    %{ctx | ui: ui, outcomes: effects ++ react_outcomes}
  end
end
