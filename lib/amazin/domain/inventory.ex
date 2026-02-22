defmodule Amazin.Domain.Inventory do
  @moduledoc """
  Domain abstraction for stock-level logic.
  Pure functions — no Ecto, no persistence, no framework dependencies.
  """

  @low_stock_threshold 5

  @type stock_status :: :in_stock | :low_stock | :out_of_stock

  @spec stock_status(integer()) :: stock_status()
  def stock_status(stock) when stock <= 0, do: :out_of_stock
  def stock_status(stock) when stock <= @low_stock_threshold, do: :low_stock
  def stock_status(_stock), do: :in_stock

  @spec check_availability([%{product: %{id: integer()}, quantity: integer()}], %{integer() => integer()}) ::
          :ok | {:error, [%{product_id: integer(), requested: integer(), available: integer()}]}
  def check_availability(items, stock_levels) do
    unavailable =
      items
      |> Enum.filter(fn item ->
        available = Map.get(stock_levels, item.product.id, 0)
        item.quantity > available
      end)
      |> Enum.map(fn item ->
        %{
          product_id: item.product.id,
          requested: item.quantity,
          available: Map.get(stock_levels, item.product.id, 0)
        }
      end)

    if unavailable == [], do: :ok, else: {:error, unavailable}
  end
end
