defmodule Amazin.Interceptors.UIDispatch do
  @moduledoc "Enter-phase interceptor: dispatches the event to CartUI."
  use Amazin.Interceptor
  alias Amazin.UI.CartUI

  @impl true
  def enter(%Context{event: event, data: data, ui: ui} = ctx) do
    {new_ui, outcomes} = CartUI.handle(event, data, ui)
    %{ctx | ui: new_ui, outcomes: ctx.outcomes ++ outcomes}
  end
end
