defmodule Amazin.Pages.CartPageTest do
  @moduledoc """
  Pure unit tests for CartPage — no Phoenix, no Ecto, no Mox.

  The test data is plain maps/structs that satisfy the shape contracts
  CartPage expects (items with .id, .quantity, .product.id, .product.amount,
  etc.), proving the Page module is truly decoupled from persistence.

  Handlers that produce multiple effects return a list of outcomes
  (Guideline 24). Handlers with a single effect return a bare tuple;
  the LiveView's `List.wrap` normalizes both shapes.
  """
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

  defp page_with_items(items) do
    CartPage.new(42, items)
  end

  # -- new/2 ------------------------------------------------------------------

  describe "new/2" do
    test "initializes with items, total, and idle checkout" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{id: 1, amount: 1000})})]
      page = CartPage.new(99, items)

      assert page.cart_id == 99
      assert page.items == items
      assert page.total == Money.new(2000)
      assert page.checkout_status == :idle
    end

    test "empty cart has zero total" do
      page = CartPage.new(1, [])
      assert page.total == Money.new(0)
    end
  end

  # -- update_quantity --------------------------------------------------------

  describe "handle(:update_quantity, ...)" do
    test "increments item quantity and recalculates total" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      page = page_with_items(items)

      {new_page, {:quantity_changed, updated}} =
        CartPage.handle(:update_quantity, %{item_id: 1, delta: 1}, page)

      assert updated.quantity == 2
      assert new_page.total == Money.new(1000)
    end

    test "decrements item quantity but floors at 1" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      page = page_with_items(items)

      {new_page, {:quantity_changed, updated}} =
        CartPage.handle(:update_quantity, %{item_id: 1, delta: -1}, page)

      assert updated.quantity == 1
      assert new_page.total == Money.new(500)
    end

    test "does not affect other items" do
      items = [
        make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, quantity: 3, product: make_product(%{id: 20, amount: 100})})
      ]
      page = page_with_items(items)

      {new_page, {:quantity_changed, _}} =
        CartPage.handle(:update_quantity, %{item_id: 1, delta: 2}, page)

      unchanged = Enum.find(new_page.items, &(&1.id == 2))
      assert unchanged.quantity == 3
    end
  end

  # -- remove_item ------------------------------------------------------------

  describe "handle(:remove_item, ...)" do
    test "removes the item and recalculates total" do
      items = [
        make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, quantity: 2, product: make_product(%{id: 20, amount: 300})})
      ]
      page = page_with_items(items)

      {new_page, {:item_removed, removed}} =
        CartPage.handle(:remove_item, %{item_id: 1}, page)

      assert removed.id == 1
      assert length(new_page.items) == 1
      assert new_page.total == Money.new(600)
    end

    test "removing nonexistent item returns nil" do
      page = page_with_items([make_item(%{id: 1})])

      {new_page, {:item_removed, nil}} =
        CartPage.handle(:remove_item, %{item_id: 999}, page)

      assert length(new_page.items) == 1
    end
  end

  # -- checkout ---------------------------------------------------------------

  describe "handle(:checkout, ...)" do
    test "with available stock, returns checkout_ready + flash outcomes" do
      items = [
        make_item(%{id: 1, quantity: 2, product: make_product(%{id: 10, amount: 1000, name: "Widget"})}),
        make_item(%{id: 2, quantity: 1, product: make_product(%{id: 20, amount: 500, name: "Gadget"})})
      ]
      page = page_with_items(items)
      stock = %{10 => 5, 20 => 10}

      {new_page, outcomes} =
        CartPage.handle(:checkout, %{stock_levels: stock}, page)

      assert new_page.checkout_status == :processing
      assert {:checkout_ready, line_items, metadata} = hd(outcomes)
      assert length(line_items) == 2
      assert metadata["cart_id"] == 42
      assert {:flash, :info, _} = List.last(outcomes)
    end

    test "with empty cart, returns flash error" do
      page = page_with_items([])

      {_page, [{:flash, :error, "Your cart is empty"}]} =
        CartPage.handle(:checkout, %{stock_levels: %{}}, page)
    end

    test "with insufficient stock, returns flash error" do
      items = [make_item(%{id: 1, quantity: 5, product: make_product(%{id: 10, amount: 1000})})]
      page = page_with_items(items)
      stock = %{10 => 2}

      {unchanged_page, [{:flash, :error, msg}]} =
        CartPage.handle(:checkout, %{stock_levels: stock}, page)

      assert unchanged_page.checkout_status == :idle
      assert msg =~ "out of stock"
    end
  end

  # -- checkout_complete / checkout_failed ------------------------------------

  describe "handle(:checkout_complete, ...)" do
    test "sets complete status and returns redirect" do
      page = %{page_with_items([]) | checkout_status: :processing}

      {new_page, {:redirect, url}} =
        CartPage.handle(:checkout_complete, %{url: "https://stripe.com/pay"}, page)

      assert new_page.checkout_status == :complete
      assert url == "https://stripe.com/pay"
    end
  end

  describe "handle(:checkout_failed, ...)" do
    test "sets error status and returns flash error outcome" do
      page = %{page_with_items([]) | checkout_status: :processing}

      {new_page, [{:flash, :error, msg}]} =
        CartPage.handle(:checkout_failed, %{}, page)

      assert new_page.checkout_status == :error
      assert msg =~ "Checkout failed"
    end
  end

  # -- stock_changed ----------------------------------------------------------

  describe "handle(:stock_changed, ...)" do
    test "updates product stock on matching item" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      page = page_with_items(items)

      {new_page, :noop} =
        CartPage.handle(:stock_changed, %{product_id: 10, new_stock: 3}, page)

      updated = hd(new_page.items)
      assert updated.product.stock == 3
    end

    test "no-ops on non-matching product" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      page = page_with_items(items)

      {new_page, :noop} =
        CartPage.handle(:stock_changed, %{product_id: 999, new_stock: 0}, page)

      assert hd(new_page.items).product.stock == 10
    end
  end
end
