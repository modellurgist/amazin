defmodule Amazin.Domain.PricingTest do
  use ExUnit.Case, async: true

  alias Amazin.Domain.Pricing

  describe "line_total/2" do
    test "multiplies unit amount by quantity" do
      assert Pricing.line_total(1000, 3) == 3000
    end

    test "handles zero quantity" do
      assert Pricing.line_total(500, 0) == 0
    end
  end

  describe "cart_total/1" do
    test "sums line totals across items" do
      items = [
        %{product: %{amount: 1000}, quantity: 2},
        %{product: %{amount: 2500}, quantity: 1}
      ]

      total = Pricing.cart_total(items)
      assert total == Money.new(4500)
    end

    test "returns zero for empty cart" do
      assert Pricing.cart_total([]) == Money.new(0)
    end
  end
end
