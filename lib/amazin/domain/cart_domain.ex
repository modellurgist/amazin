defmodule Amazin.Domain.CartDomain do
  @moduledoc """
  Domain state machine for V14 Dual + Signals.

  Owns all business state (items, totals, promo, checkout workflow).
  Emits `signal(name)` outcomes for cross-machine coordination —
  the LiveView routes these to `CartUI.react/2`.

  CartDomain never imports or calls CartUI; the signal is the only
  coupling surface, and it flows through the LiveView dispatcher.
  """

  import Amazin.Outcome

  alias Amazin.Domain.{Pricing, Checkout, Inventory, Shipping}

  defstruct [
    :cart_id,
    items: [],
    saved_items: [],
    gift_wrapped_ids: MapSet.new(),
    gift_wrap_total: Money.new(0),
    shipping_method: :standard,
    shipping_cost: Money.new(0),
    pending_undo: nil,
    total: Money.new(0),
    subtotal: Money.new(0),
    discount: Money.new(0),
    item_count: 0,
    promo_code: nil,
    promo_percentage: nil,
    checkout_status: :idle
  ]

  @type t :: %__MODULE__{
          cart_id: integer(),
          items: list(),
          saved_items: list(),
          gift_wrapped_ids: MapSet.t(),
          gift_wrap_total: Money.t(),
          shipping_method: :standard | :express | :overnight,
          shipping_cost: Money.t(),
          pending_undo: map() | nil,
          total: Money.t(),
          subtotal: Money.t(),
          discount: Money.t(),
          item_count: non_neg_integer(),
          promo_code: String.t() | nil,
          promo_percentage: non_neg_integer() | nil,
          checkout_status: :idle | :processing | :complete | :error
        }

  @spec new(integer(), [map()]) :: t()
  def new(cart_id, items) do
    %__MODULE__{cart_id: cart_id, items: items} |> recalc()
  end

  # ── Event handlers ─────────────────────────────────────────────────────

  @spec handle(atom(), map(), t()) :: {t(), [term()]}

  def handle(:update_quantity, %{item_id: item_id, delta: delta}, state) do
    items = update_item_qty(state.items, item_id, delta)
    updated = Enum.find(items, &(&1.id == item_id))
    state = recalc(%{state | items: items})

    {state,
     [
       persist_quantity(state.cart_id, item_id, updated.quantity),
       stream_insert(:cart_items, updated)
     ]}
  end

  def handle(:remove_item, %{item_id: item_id}, state) do
    {removed, remaining} = pop_item(state.items, item_id)

    if removed do
      gift_ids = MapSet.delete(state.gift_wrapped_ids, item_id)
      state = recalc(%{state | items: remaining, gift_wrapped_ids: gift_ids, pending_undo: %{item: removed}})

      {state, [
        stream_delete(:cart_items, removed),
        push_event("item_removed", %{id: item_id}),
        flash(:info, "Item removed"),
        start_undo_timer(item_id),
        signal(:item_removed)
      ]}
    else
      {state, []}
    end
  end

  def handle(:checkout, %{stock_levels: stock}, state) do
    case Checkout.validate(state.items) do
      {:ok, items} ->
        case Inventory.check_availability(items, stock) do
          :ok ->
            line_items = Checkout.prepare_line_items(items)
            metadata = %{"cart_id" => state.cart_id}

            {%{state | checkout_status: :processing},
             [
               start_checkout(line_items, metadata),
               flash(:info, "Processing payment..."),
               signal(:checkout_started)
             ]}

          {:error, _} ->
            {state, [flash(:error, "Some items are out of stock")]}
        end

      {:error, :empty_cart} ->
        {state, [flash(:error, "Your cart is empty")]}
    end
  end

  def handle(:checkout_complete, %{url: url}, state) do
    {%{state | checkout_status: :complete}, [redirect(url)]}
  end

  def handle(:checkout_failed, _data, state) do
    {%{state | checkout_status: :error},
     [flash(:error, "Checkout failed. Please try again.")]}
  end

  def handle(:stock_changed, %{product_id: pid, new_stock: stock}, state) do
    items = update_product_stock(state.items, pid, stock)
    updated = Enum.find(items, &(&1.product.id == pid))
    state = %{state | items: items}
    outcomes = if updated, do: [stream_insert(:cart_items, updated)], else: []
    {state, outcomes}
  end

  def handle(:apply_promo, %{code: code}, state) do
    case Pricing.validate_promo(code) do
      {:ok, pct} ->
        state = recalc(%{state | promo_code: code, promo_percentage: pct})
        {state, [flash(:info, "Promo code applied!"), signal(:promo_applied)]}

      {:error, :invalid_code} ->
        {state, [flash(:error, "Invalid promo code")]}
    end
  end

  def handle(:save_for_later, %{item_id: item_id}, state) do
    {saved, remaining} = pop_item(state.items, item_id)

    if saved do
      gift_ids = MapSet.delete(state.gift_wrapped_ids, item_id)
      state = recalc(%{state | items: remaining, saved_items: state.saved_items ++ [saved], gift_wrapped_ids: gift_ids})

      {state, [
        stream_delete(:cart_items, saved),
        stream_insert(:saved_items, saved),
        flash(:info, "Saved for later"),
        signal(:item_saved)
      ]}
    else
      {state, []}
    end
  end

  def handle(:move_to_cart, %{item_id: item_id}, state) do
    {restored, remaining_saved} = pop_item(state.saved_items, item_id)

    if restored do
      state = recalc(%{state | items: state.items ++ [restored], saved_items: remaining_saved})

      {state, [
        stream_insert(:cart_items, restored),
        stream_delete(:saved_items, restored),
        flash(:info, "Moved to cart"),
        signal(:item_restored)
      ]}
    else
      {state, []}
    end
  end

  def handle(:toggle_gift_wrap, %{item_id: item_id}, state) do
    gift_ids = toggle_set(state.gift_wrapped_ids, item_id)
    state = recalc(%{state | gift_wrapped_ids: gift_ids})
    item = Enum.find(state.items, &(&1.id == item_id))

    if item do
      {state, [stream_insert(:cart_items, item)]}
    else
      {state, []}
    end
  end

  def handle(:select_shipping, %{method: method}, state) do
    state = recalc(%{state | shipping_method: method})
    {state, [signal(:shipping_changed)]}
  end

  def handle(:undo_remove, _data, state) do
    case state.pending_undo do
      %{item: item} ->
        state = recalc(%{state | items: state.items ++ [item], pending_undo: nil})

        {state, [
          stream_insert(:cart_items, item),
          cancel_undo_timer(),
          flash(:info, "Item restored"),
          signal(:item_restored)
        ]}

      nil ->
        {state, []}
    end
  end

  def handle(:undo_expired, _data, state) do
    case state.pending_undo do
      %{item: item} ->
        {%{state | pending_undo: nil}, [persist_remove(state.cart_id, item.id)]}

      nil ->
        {state, []}
    end
  end

  def handle(_event, _data, state), do: {state, []}

  # ── Private helpers ────────────────────────────────────────────────────

  defp recalc(state) do
    sub = Pricing.subtotal_cents(state.items)
    {total_after_disc, disc} = Pricing.apply_discount(sub, state.promo_percentage || 0)
    gw = Pricing.gift_wrap_total(MapSet.size(state.gift_wrapped_ids))
    ship = Shipping.calculate(state.shipping_method, sub)

    %{state |
      subtotal: Money.new(sub),
      total: Money.new(total_after_disc + gw + ship),
      discount: Money.new(disc),
      gift_wrap_total: Money.new(gw),
      shipping_cost: Money.new(ship),
      item_count: Pricing.item_count(state.items)}
  end

  defp update_item_qty(items, item_id, delta) do
    Enum.map(items, fn item ->
      if item.id == item_id, do: %{item | quantity: max(1, item.quantity + delta)}, else: item
    end)
  end

  defp pop_item(items, item_id) do
    case Enum.split_with(items, &(&1.id == item_id)) do
      {[removed | _], remaining} -> {removed, remaining}
      {[], remaining} -> {nil, remaining}
    end
  end

  defp update_product_stock(items, pid, new_stock) do
    Enum.map(items, fn item ->
      if item.product.id == pid,
        do: %{item | product: %{item.product | stock: new_stock}},
        else: item
    end)
  end

  defp toggle_set(set, item) do
    if MapSet.member?(set, item), do: MapSet.delete(set, item), else: MapSet.put(set, item)
  end
end
