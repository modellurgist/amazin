defmodule Amazin.Interceptors.InjectStock do
  @moduledoc """
  Enter-phase interceptor: reads current stock levels from the database
  and injects them into `ctx.data[:stock_levels]`.

  Used only in the `:checkout` pipeline so the domain handler receives
  stock without the LiveView needing to know about product queries.
  """
  use Amazin.Interceptor
  alias Amazin.Foundation.Products

  @impl true
  def enter(%Context{domain: domain} = ctx) do
    product_ids = Enum.map(domain.items, & &1.product.id)
    stock = Products.stock_levels(product_ids)
    %{ctx | data: Map.put(ctx.data, :stock_levels, stock)}
  end
end
