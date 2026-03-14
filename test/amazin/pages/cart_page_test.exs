defmodule Amazin.Pages.CartPageTest do
  use ExUnit.Case, async: true

  alias Amazin.Pages.CartPage

  defp make_product(attrs) do
    Map.merge(
      %{id: 1, name: "Widget", description: "A widget", amount: 1000, stock: 10, thumbnail: "w.png"},
      attrs
    )
  end

  defp make_item(attrs) do
    Map.merge(%{id: 1, quantity: 1, product: make_product(%{})}, attrs)
  end

  defp page_with_items(items), do: CartPage.new(42, items)

  describe "new/2" do
    test "initializes with items and computed totals" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{amount: 1000})})]
      page = CartPage.new(99, items)

      assert page.domain.cart_id == 99
      assert page.domain.total == Money.new(2000)
      assert page.domain.item_count == 2
      assert page.checkout_status == :idle
      assert page.ui.active_tab == :items
    end
  end

  describe "handle(:switch_tab, ...)" do
    test "changes active tab without touching domain" do
      page = page_with_items([])
      {new_page, []} = CartPage.handle(:switch_tab, %{tab: :summary}, page)

      assert new_page.ui.active_tab == :summary
      assert new_page.domain == page.domain
    end
  end

  describe "handle(:update_quantity, ...)" do
    test "increments and recalculates" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      page = page_with_items(items)

      {new_page, outcomes} = CartPage.handle(:update_quantity, %{item_id: 1, delta: 1}, page)

      assert new_page.domain.total == Money.new(1000)
      assert {:persist_quantity, 42, 1, 2} in outcomes
      assert match?({:stream_insert, :cart_items, _}, Enum.find(outcomes, &match?({:stream_insert, _, _}, &1)))
    end

    test "does not decrement below 1" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      page = page_with_items(items)

      {new_page, outcomes} = CartPage.handle(:update_quantity, %{item_id: 1, delta: -1}, page)

      assert hd(new_page.domain.items).quantity == 1
      assert {:persist_quantity, 42, 1, 1} in outcomes
    end
  end

  describe "handle(:remove_item, ...)" do
    test "removes and returns outcomes" do
      items = [
        make_item(%{id: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, product: make_product(%{id: 20, amount: 300})})
      ]
      page = page_with_items(items)

      {new_page, outcomes} = CartPage.handle(:remove_item, %{item_id: 1}, page)

      assert length(new_page.domain.items) == 1
      assert {:persist_remove, 42, 1} in outcomes
      assert {:push_event, "item_removed", %{id: 1}} in outcomes
      assert {:flash, :info, "Item removed"} in outcomes
    end

    test "removing nonexistent item is a no-op" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, amount: 500})})]
      page = page_with_items(items)

      {new_page, outcomes} = CartPage.handle(:remove_item, %{item_id: 999}, page)

      assert length(new_page.domain.items) == 1
      assert outcomes == []
    end
  end

  describe "handle(:checkout, ...)" do
    test "with available stock returns start_checkout" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{id: 10, amount: 1000})})]
      page = page_with_items(items)

      {new_page, outcomes} =
        CartPage.handle(:checkout, %{stock_levels: %{10 => 5}}, page)

      assert new_page.checkout_status == :processing
      assert Enum.any?(outcomes, &match?({:start_checkout, _, _}, &1))
      assert Enum.any?(outcomes, &match?({:flash, :info, _}, &1))
    end

    test "empty cart returns flash error" do
      page = page_with_items([])

      {_page, outcomes} = CartPage.handle(:checkout, %{stock_levels: %{}}, page)

      assert {:flash, :error, "Your cart is empty"} in outcomes
    end

    test "out of stock returns flash error" do
      items = [make_item(%{id: 1, quantity: 10, product: make_product(%{id: 10, amount: 1000})})]
      page = page_with_items(items)

      {new_page, outcomes} =
        CartPage.handle(:checkout, %{stock_levels: %{10 => 2}}, page)

      assert new_page.checkout_status == :idle
      assert {:flash, :error, "Some items are out of stock"} in outcomes
    end
  end

  describe "handle(:checkout_complete, ...)" do
    test "returns redirect" do
      page = %{page_with_items([]) | checkout_status: :processing}

      {new_page, outcomes} =
        CartPage.handle(:checkout_complete, %{url: "https://stripe.com"}, page)

      assert new_page.checkout_status == :complete
      assert {:redirect, "https://stripe.com"} in outcomes
    end
  end

  describe "handle(:checkout_failed, ...)" do
    test "returns error flash" do
      page = %{page_with_items([]) | checkout_status: :processing}

      {new_page, outcomes} = CartPage.handle(:checkout_failed, %{}, page)

      assert new_page.checkout_status == :error
      assert Enum.any?(outcomes, &match?({:flash, :error, _}, &1))
    end
  end

  describe "handle(:stock_changed, ...)" do
    test "updates product stock" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      page = page_with_items(items)

      {new_page, outcomes} =
        CartPage.handle(:stock_changed, %{product_id: 10, new_stock: 3}, page)

      assert hd(new_page.domain.items).product.stock == 3
      assert Enum.any?(outcomes, &match?({:stream_insert, :cart_items, _}, &1))
    end

    test "ignores unknown product_id" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      page = page_with_items(items)

      {new_page, outcomes} =
        CartPage.handle(:stock_changed, %{product_id: 999, new_stock: 3}, page)

      assert hd(new_page.domain.items).product.stock == 10
      assert outcomes == []
    end
  end

  describe "handle(:apply_promo, ...)" do
    test "valid code sets discount" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{amount: 1000})})]
      page = page_with_items(items)

      {new_page, outcomes} = CartPage.handle(:apply_promo, %{code: "SAVE10"}, page)

      assert new_page.domain.promo_code == "SAVE10"
      assert new_page.domain.discount == Money.new(200)
      assert new_page.domain.total == Money.new(1800)
      assert new_page.ui.promo_error == nil
      assert Enum.any?(outcomes, &match?({:flash, :info, _}, &1))
    end

    test "invalid code sets error" do
      page = page_with_items([])

      {new_page, outcomes} = CartPage.handle(:apply_promo, %{code: "BOGUS"}, page)

      assert new_page.ui.promo_error == "Invalid promo code"
      assert Enum.any?(outcomes, &match?({:flash, :error, _}, &1))
    end
  end
end
