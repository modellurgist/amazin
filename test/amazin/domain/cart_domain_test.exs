defmodule Amazin.Domain.CartDomainTest do
  @moduledoc """
  Pure unit tests for CartDomain — no Phoenix, no Ecto, no Mox.

  Assertions use `Outcome` constructor calls so misspelling an outcome
  name produces a compile error. Signal emission is verified by checking
  for `{:signal, name}` tuples in the outcome list.
  """
  use ExUnit.Case, async: true

  alias Amazin.Domain.CartDomain
  alias Amazin.Outcome

  # ── Test helpers ────────────────────────────────────────────────────────

  defp make_product(attrs) do
    Map.merge(
      %{id: 1, name: "Widget", description: "A widget", amount: 1000, stock: 10, thumbnail: "w.png"},
      attrs
    )
  end

  defp make_item(attrs) do
    Map.merge(%{id: 1, quantity: 1, product: make_product(%{})}, attrs)
  end

  defp domain_with_items(items) do
    CartDomain.new(42, items)
  end

  # ── new/2 ──────────────────────────────────────────────────────────────

  describe "new/2" do
    test "initializes with items and computed totals (including shipping)" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{id: 1, amount: 1000})})]
      state = CartDomain.new(99, items)

      assert state.cart_id == 99
      assert state.items == items
      assert state.subtotal == Money.new(2000)
      assert state.discount == Money.new(0)
      assert state.item_count == 2
      assert state.shipping_method == :standard
      assert state.shipping_cost == Money.new(599)
      assert state.gift_wrap_total == Money.new(0)
      assert state.total == Money.new(2599)
      assert state.checkout_status == :idle
      assert state.promo_code == nil
      assert state.saved_items == []
      assert state.gift_wrapped_ids == MapSet.new()
      assert state.pending_undo == nil
    end

    test "empty cart has zero totals and zero shipping" do
      state = CartDomain.new(1, [])

      assert state.total == Money.new(0)
      assert state.subtotal == Money.new(0)
      assert state.shipping_cost == Money.new(0)
      assert state.item_count == 0
    end

    test "standard shipping is free when subtotal >= 5000" do
      items = [make_item(%{id: 1, quantity: 5, product: make_product(%{id: 1, amount: 1000})})]
      state = CartDomain.new(1, items)

      assert state.subtotal == Money.new(5000)
      assert state.shipping_cost == Money.new(0)
      assert state.total == Money.new(5000)
    end
  end

  # ── update_quantity ────────────────────────────────────────────────────

  describe "handle(:update_quantity, ...)" do
    test "increments item quantity and recalculates totals" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:update_quantity, %{item_id: 1, delta: 1}, state)

      updated = Enum.find(new_state.items, &(&1.id == 1))
      assert updated.quantity == 2
      assert new_state.subtotal == Money.new(1000)
      assert new_state.shipping_cost == Money.new(599)
      assert new_state.total == Money.new(1599)
      assert new_state.item_count == 2

      assert outcomes == [
               Outcome.persist_quantity(42, 1, 2),
               Outcome.stream_insert(:cart_items, updated)
             ]
    end

    test "decrements but floors quantity at 1" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 1, amount: 500})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:update_quantity, %{item_id: 1, delta: -1}, state)

      updated = Enum.find(new_state.items, &(&1.id == 1))
      assert updated.quantity == 1
      assert new_state.subtotal == Money.new(500)
      assert new_state.shipping_cost == Money.new(599)
      assert new_state.total == Money.new(1099)

      assert outcomes == [
               Outcome.persist_quantity(42, 1, 1),
               Outcome.stream_insert(:cart_items, updated)
             ]
    end

    test "does not affect other items" do
      items = [
        make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, quantity: 3, product: make_product(%{id: 20, amount: 100})})
      ]
      state = domain_with_items(items)

      {new_state, _outcomes} =
        CartDomain.handle(:update_quantity, %{item_id: 1, delta: 2}, state)

      unchanged = Enum.find(new_state.items, &(&1.id == 2))
      assert unchanged.quantity == 3
    end
  end

  # ── remove_item ────────────────────────────────────────────────────────

  describe "handle(:remove_item, ...)" do
    test "removes item, stores pending_undo, emits start_undo_timer + signal(:item_removed)" do
      items = [
        make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, quantity: 2, product: make_product(%{id: 20, amount: 300})})
      ]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:remove_item, %{item_id: 1}, state)

      removed = Enum.find(items, &(&1.id == 1))

      assert length(new_state.items) == 1
      assert new_state.subtotal == Money.new(600)
      assert new_state.shipping_cost == Money.new(599)
      assert new_state.total == Money.new(1199)
      assert new_state.item_count == 2
      assert new_state.pending_undo == %{item: removed}

      assert outcomes == [
               Outcome.stream_delete(:cart_items, removed),
               Outcome.push_event("item_removed", %{id: 1}),
               Outcome.flash(:info, "Item removed"),
               Outcome.start_undo_timer(1),
               Outcome.signal(:item_removed)
             ]
    end

    test "removing item clears its gift wrap" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = %{domain_with_items(items) | gift_wrapped_ids: MapSet.new([1])}
      state = %{state | gift_wrap_total: Money.new(299)}

      {new_state, _outcomes} =
        CartDomain.handle(:remove_item, %{item_id: 1}, state)

      refute MapSet.member?(new_state.gift_wrapped_ids, 1)
      assert new_state.gift_wrap_total == Money.new(0)
    end

    test "removing nonexistent item returns empty outcomes" do
      state = domain_with_items([make_item(%{id: 1})])

      {new_state, outcomes} =
        CartDomain.handle(:remove_item, %{item_id: 999}, state)

      assert length(new_state.items) == 1
      assert outcomes == []
    end
  end

  # ── save_for_later ──────────────────────────────────────────────────────

  describe "handle(:save_for_later, ...)" do
    test "moves item from cart to saved_items and emits signal(:item_saved)" do
      items = [
        make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})}),
        make_item(%{id: 2, quantity: 2, product: make_product(%{id: 20, amount: 300})})
      ]
      state = domain_with_items(items)
      item_1 = Enum.find(items, &(&1.id == 1))

      {new_state, outcomes} =
        CartDomain.handle(:save_for_later, %{item_id: 1}, state)

      assert length(new_state.items) == 1
      assert length(new_state.saved_items) == 1
      assert hd(new_state.saved_items).id == 1
      assert new_state.subtotal == Money.new(600)

      assert outcomes == [
               Outcome.stream_delete(:cart_items, item_1),
               Outcome.stream_insert(:saved_items, item_1),
               Outcome.flash(:info, "Saved for later"),
               Outcome.signal(:item_saved)
             ]
    end

    test "clears gift wrap when saving item" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = %{domain_with_items(items) | gift_wrapped_ids: MapSet.new([1])}

      {new_state, _outcomes} =
        CartDomain.handle(:save_for_later, %{item_id: 1}, state)

      refute MapSet.member?(new_state.gift_wrapped_ids, 1)
    end

    test "saving nonexistent item returns empty outcomes" do
      state = domain_with_items([make_item(%{id: 1})])

      {_state, outcomes} =
        CartDomain.handle(:save_for_later, %{item_id: 999}, state)

      assert outcomes == []
    end
  end

  # ── move_to_cart ────────────────────────────────────────────────────────

  describe "handle(:move_to_cart, ...)" do
    test "moves item from saved_items back to cart and emits signal(:item_restored)" do
      item = make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})})
      state = %{domain_with_items([]) | saved_items: [item]}

      {new_state, outcomes} =
        CartDomain.handle(:move_to_cart, %{item_id: 1}, state)

      assert length(new_state.items) == 1
      assert new_state.saved_items == []
      assert new_state.subtotal == Money.new(500)

      assert outcomes == [
               Outcome.stream_insert(:cart_items, item),
               Outcome.stream_delete(:saved_items, item),
               Outcome.flash(:info, "Moved to cart"),
               Outcome.signal(:item_restored)
             ]
    end

    test "moving nonexistent saved item returns empty outcomes" do
      state = %{domain_with_items([]) | saved_items: [make_item(%{id: 1})]}

      {_state, outcomes} =
        CartDomain.handle(:move_to_cart, %{item_id: 999}, state)

      assert outcomes == []
    end
  end

  # ── toggle_gift_wrap ────────────────────────────────────────────────────

  describe "handle(:toggle_gift_wrap, ...)" do
    test "enables gift wrap for an item and adds to total" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:toggle_gift_wrap, %{item_id: 1}, state)

      assert MapSet.member?(new_state.gift_wrapped_ids, 1)
      assert new_state.gift_wrap_total == Money.new(299)
      assert new_state.total == Money.new(1000 + 299 + 599)

      item = Enum.find(new_state.items, &(&1.id == 1))
      assert outcomes == [Outcome.stream_insert(:cart_items, item)]
    end

    test "disables gift wrap when toggled again" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = %{domain_with_items(items) | gift_wrapped_ids: MapSet.new([1])}

      {new_state, _outcomes} =
        CartDomain.handle(:toggle_gift_wrap, %{item_id: 1}, state)

      refute MapSet.member?(new_state.gift_wrapped_ids, 1)
      assert new_state.gift_wrap_total == Money.new(0)
    end

    test "toggling nonexistent item returns empty outcomes" do
      state = domain_with_items([make_item(%{id: 1})])

      {_state, outcomes} =
        CartDomain.handle(:toggle_gift_wrap, %{item_id: 999}, state)

      assert outcomes == []
    end
  end

  # ── select_shipping ─────────────────────────────────────────────────────

  describe "handle(:select_shipping, ...)" do
    test "selects express shipping and recalculates total" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:select_shipping, %{method: :express}, state)

      assert new_state.shipping_method == :express
      assert new_state.shipping_cost == Money.new(1299)
      assert new_state.total == Money.new(1000 + 1299)

      assert outcomes == [Outcome.signal(:shipping_changed)]
    end

    test "selects overnight shipping" do
      items = [make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 1000})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:select_shipping, %{method: :overnight}, state)

      assert new_state.shipping_method == :overnight
      assert new_state.shipping_cost == Money.new(2499)
      assert new_state.total == Money.new(1000 + 2499)

      assert outcomes == [Outcome.signal(:shipping_changed)]
    end

    test "standard shipping is free above $50" do
      items = [make_item(%{id: 1, quantity: 6, product: make_product(%{id: 10, amount: 1000})})]
      state = domain_with_items(items)

      {new_state, _outcomes} =
        CartDomain.handle(:select_shipping, %{method: :standard}, state)

      assert new_state.shipping_cost == Money.new(0)
      assert new_state.total == Money.new(6000)
    end
  end

  # ── undo_remove ─────────────────────────────────────────────────────────

  describe "handle(:undo_remove, ...)" do
    test "restores pending item to cart and emits signal(:item_restored)" do
      item = make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})})
      state = %{domain_with_items([]) | pending_undo: %{item: item}}

      {new_state, outcomes} =
        CartDomain.handle(:undo_remove, %{}, state)

      assert length(new_state.items) == 1
      assert hd(new_state.items).id == 1
      assert new_state.pending_undo == nil
      assert new_state.subtotal == Money.new(500)

      assert outcomes == [
               Outcome.stream_insert(:cart_items, item),
               Outcome.cancel_undo_timer(),
               Outcome.flash(:info, "Item restored"),
               Outcome.signal(:item_restored)
             ]
    end

    test "no-ops when there is no pending undo" do
      state = domain_with_items([])

      {_state, outcomes} =
        CartDomain.handle(:undo_remove, %{}, state)

      assert outcomes == []
    end
  end

  # ── undo_expired ────────────────────────────────────────────────────────

  describe "handle(:undo_expired, ...)" do
    test "persists removal when undo timer expires" do
      item = make_item(%{id: 1, quantity: 1, product: make_product(%{id: 10, amount: 500})})
      state = %{domain_with_items([]) | pending_undo: %{item: item}}

      {new_state, outcomes} =
        CartDomain.handle(:undo_expired, %{}, state)

      assert new_state.pending_undo == nil
      assert outcomes == [Outcome.persist_remove(42, 1)]
    end

    test "no-ops when there is no pending undo" do
      state = domain_with_items([])

      {_state, outcomes} =
        CartDomain.handle(:undo_expired, %{}, state)

      assert outcomes == []
    end
  end

  # ── checkout ───────────────────────────────────────────────────────────

  describe "handle(:checkout, ...)" do
    test "with available stock, emits start_checkout + signal(:checkout_started)" do
      items = [
        make_item(%{id: 1, quantity: 2, product: make_product(%{id: 10, amount: 1000, name: "Widget"})}),
        make_item(%{id: 2, quantity: 1, product: make_product(%{id: 20, amount: 500, name: "Gadget"})})
      ]
      state = domain_with_items(items)
      stock = %{10 => 5, 20 => 10}

      {new_state, outcomes} =
        CartDomain.handle(:checkout, %{stock_levels: stock}, state)

      assert new_state.checkout_status == :processing

      assert [{:start_checkout, line_items, metadata}, {:flash, :info, _}, {:signal, :checkout_started}] = outcomes
      assert length(line_items) == 2
      assert metadata["cart_id"] == 42
    end

    test "with empty cart, returns flash error" do
      state = domain_with_items([])

      {_state, outcomes} =
        CartDomain.handle(:checkout, %{stock_levels: %{}}, state)

      assert outcomes == [Outcome.flash(:error, "Your cart is empty")]
    end

    test "with insufficient stock, returns flash error" do
      items = [make_item(%{id: 1, quantity: 5, product: make_product(%{id: 10, amount: 1000})})]
      state = domain_with_items(items)
      stock = %{10 => 2}

      {unchanged_state, outcomes} =
        CartDomain.handle(:checkout, %{stock_levels: stock}, state)

      assert unchanged_state.checkout_status == :idle
      assert [{:flash, :error, msg}] = outcomes
      assert msg =~ "out of stock"
    end
  end

  # ── checkout_complete / checkout_failed ────────────────────────────────

  describe "handle(:checkout_complete, ...)" do
    test "sets complete status and returns redirect" do
      state = %{domain_with_items([]) | checkout_status: :processing}

      {new_state, outcomes} =
        CartDomain.handle(:checkout_complete, %{url: "https://stripe.com/pay"}, state)

      assert new_state.checkout_status == :complete
      assert outcomes == [Outcome.redirect("https://stripe.com/pay")]
    end
  end

  describe "handle(:checkout_failed, ...)" do
    test "sets error status and returns flash error" do
      state = %{domain_with_items([]) | checkout_status: :processing}

      {new_state, outcomes} =
        CartDomain.handle(:checkout_failed, %{}, state)

      assert new_state.checkout_status == :error
      assert [{:flash, :error, msg}] = outcomes
      assert msg =~ "Checkout failed"
    end
  end

  # ── stock_changed ──────────────────────────────────────────────────────

  describe "handle(:stock_changed, ...)" do
    test "updates product stock on matching item and streams update" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:stock_changed, %{product_id: 10, new_stock: 3}, state)

      updated = hd(new_state.items)
      assert updated.product.stock == 3
      assert outcomes == [Outcome.stream_insert(:cart_items, updated)]
    end

    test "no-ops on non-matching product" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:stock_changed, %{product_id: 999, new_stock: 0}, state)

      assert hd(new_state.items).product.stock == 10
      assert outcomes == []
    end
  end

  # ── apply_promo ────────────────────────────────────────────────────────

  describe "handle(:apply_promo, ...)" do
    test "valid code sets discount, recalculates, and emits signal(:promo_applied)" do
      items = [make_item(%{id: 1, quantity: 2, product: make_product(%{id: 1, amount: 1000})})]
      state = domain_with_items(items)

      {new_state, outcomes} =
        CartDomain.handle(:apply_promo, %{code: "SAVE10"}, state)

      assert new_state.promo_code == "SAVE10"
      assert new_state.promo_percentage == 10
      assert new_state.subtotal == Money.new(2000)
      assert new_state.discount == Money.new(200)
      assert new_state.shipping_cost == Money.new(599)
      assert new_state.total == Money.new(1800 + 599)

      assert outcomes == [
               Outcome.flash(:info, "Promo code applied!"),
               Outcome.signal(:promo_applied)
             ]
    end

    test "invalid code returns flash error without signal" do
      state = domain_with_items([make_item(%{})])

      {new_state, outcomes} =
        CartDomain.handle(:apply_promo, %{code: "BOGUS"}, state)

      assert new_state.promo_percentage == nil
      assert outcomes == [Outcome.flash(:error, "Invalid promo code")]
    end
  end

  # ── catch-all ──────────────────────────────────────────────────────────

  describe "handle (catch-all)" do
    test "unknown events return state unchanged with no outcomes" do
      state = domain_with_items([])

      {unchanged, outcomes} = CartDomain.handle(:unknown_event, %{}, state)

      assert unchanged == state
      assert outcomes == []
    end
  end
end
