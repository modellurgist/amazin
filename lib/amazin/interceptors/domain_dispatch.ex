defmodule Amazin.Interceptors.DomainDispatch do
  @moduledoc "Enter-phase interceptor: dispatches the event to CartDomain."
  use Amazin.Interceptor
  alias Amazin.Domain.CartDomain

  @impl true
  def enter(%Context{event: event, data: data, domain: domain} = ctx) do
    {new_domain, outcomes} = CartDomain.handle(event, data, domain)
    %{ctx | domain: new_domain, outcomes: ctx.outcomes ++ outcomes}
  end
end
