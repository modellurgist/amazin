defmodule Amazin.Domain.Shipping do
  @moduledoc """
  Domain abstraction for shipping cost calculations.
  Pure functions — no Ecto, no persistence, no framework dependencies.
  """

  @methods %{
    standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
    overnight: %{label: "Overnight", cost: 2499, free_above: nil}
  }

  @spec methods() :: %{atom() => map()}
  def methods, do: @methods

  @spec method_names() :: [atom()]
  def method_names, do: [:standard, :express, :overnight]

  @spec label(atom()) :: String.t()
  def label(method), do: @methods[method].label

  @spec calculate(atom(), integer()) :: integer()
  def calculate(_method, 0), do: 0

  def calculate(method, subtotal_cents) when subtotal_cents > 0 do
    info = Map.fetch!(@methods, method)

    case info[:free_above] do
      nil -> info.cost
      threshold when subtotal_cents >= threshold -> 0
      _ -> info.cost
    end
  end
end
