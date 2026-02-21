defmodule Amazin.Domain.Pricing do
  @moduledoc """
  Domain abstraction for price calculations.
  Pure functions on data — no Ecto, no persistence, no framework dependencies.
  """

  @spec line_total(integer(), integer()) :: integer()
  def line_total(unit_amount, quantity) when is_integer(unit_amount) and is_integer(quantity) do
    unit_amount * quantity
  end

  @spec cart_total([%{product: %{amount: integer()}, quantity: integer()}]) :: Money.t()
  def cart_total(items) do
    items
    |> Enum.map(fn item -> line_total(item.product.amount, item.quantity) end)
    |> Enum.sum()
    |> Money.new()
  end
end
