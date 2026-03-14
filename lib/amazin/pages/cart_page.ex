defmodule Amazin.Pages.CartPage do
  @moduledoc """
  Embedded Dual Page — collapses UI and Domain into a single Page module.
  Handlers update one or both sub-structs atomically and return {page, [outcome]}.
  """

  import Amazin.Outcome

  alias Amazin.Domain.{Pricing, Checkout, Inventory}

  # ── Embedded sub-structs ──────────────────────────────────────────────

  defmodule UI do
    @moduledoc false
    defstruct active_tab: :items,
              promo_error: nil
  end

  defmodule Domain do
    @moduledoc false
    defstruct cart_id: nil,
              items: [],
              total: Money.new(0),
              subtotal: Money.new(0),
              discount: Money.new(0),
              item_count: 0,
              promo_code: nil,
              promo_percentage: nil
  end

  # ── Top-level struct ──────────────────────────────────────────────────

  defstruct [:ui, :domain, checkout_status: :idle]

  @type t :: %__MODULE__{
          ui: UI.t(),
          domain: Domain.t(),
          checkout_status: :idle | :processing | :complete | :error
        }

  # ── Constructor ───────────────────────────────────────────────────────

  @spec new(integer(), [map()]) :: t()
  def new(cart_id, items) do
    domain = %Domain{cart_id: cart_id, items: items}
    %__MODULE__{ui: %UI{}, domain: recalc(domain)}
  end

  # ── Handlers — return {page, [outcome]} ───────────────────────────────

  @spec handle(atom(), map(), t()) :: {t(), [term()]}

  def handle(:switch_tab, %{tab: tab}, page) do
    {put_in(page.ui.active_tab, tab), []}
  end

  def handle(:update_quantity, %{item_id: item_id, delta: delta}, page) do
    items = update_item_quantity(page.domain.items, item_id, delta)
    updated_item = Enum.find(items, &(&1.id == item_id))
    domain = recalc(%{page.domain | items: items})

    {%{page | domain: domain},
     [
       persist_quantity(domain.cart_id, item_id, updated_item.quantity),
       stream_insert(:cart_items, updated_item)
     ]}
  end

  def handle(:remove_item, %{item_id: item_id}, page) do
    {removed, remaining} = pop_item(page.domain.items, item_id)
    domain = recalc(%{page.domain | items: remaining})

    outcomes =
      if removed do
        [
          persist_remove(domain.cart_id, item_id),
          stream_delete(:cart_items, removed),
          push_event("item_removed", %{id: item_id}),
          flash(:info, "Item removed")
        ]
      else
        []
      end

    {%{page | domain: domain}, outcomes}
  end

  def handle(:checkout, %{stock_levels: stock}, page) do
    case Checkout.validate(page.domain.items) do
      {:ok, items} ->
        case Inventory.check_availability(items, stock) do
          :ok ->
            line_items = Checkout.prepare_line_items(items)
            metadata = %{"cart_id" => page.domain.cart_id}

            {%{page | checkout_status: :processing},
             [start_checkout(line_items, metadata), flash(:info, "Processing payment...")]}

          {:error, _} ->
            {page, [flash(:error, "Some items are out of stock")]}
        end

      {:error, :empty_cart} ->
        {page, [flash(:error, "Your cart is empty")]}
    end
  end

  def handle(:checkout_complete, %{url: url}, page) do
    {%{page | checkout_status: :complete}, [redirect(url)]}
  end

  def handle(:checkout_failed, _data, page) do
    {%{page | checkout_status: :error}, [flash(:error, "Checkout failed. Please try again.")]}
  end

  def handle(:stock_changed, %{product_id: pid, new_stock: stock}, page) do
    items = update_product_stock(page.domain.items, pid, stock)
    updated_item = Enum.find(items, &(&1.product.id == pid))
    domain = %{page.domain | items: items}
    outcomes = if updated_item, do: [stream_insert(:cart_items, updated_item)], else: []
    {%{page | domain: domain}, outcomes}
  end

  def handle(:apply_promo, %{code: code}, page) do
    case Pricing.validate_promo(code) do
      {:ok, pct} ->
        domain = recalc(%{page.domain | promo_code: code, promo_percentage: pct})
        ui = %{page.ui | promo_error: nil}
        {%{page | domain: domain, ui: ui}, [flash(:info, "Promo code applied!")]}

      {:error, :invalid_code} ->
        ui = %{page.ui | promo_error: "Invalid promo code"}
        {%{page | ui: ui}, [flash(:error, "Invalid promo code")]}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp recalc(domain) do
    sub = Pricing.subtotal_cents(domain.items)
    {total, disc} = Pricing.apply_discount(sub, domain.promo_percentage || 0)

    %{domain |
      subtotal: Money.new(sub),
      total: Money.new(total),
      discount: Money.new(disc),
      item_count: Pricing.item_count(domain.items)}
  end

  defp update_item_quantity(items, item_id, delta) do
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

  defp update_product_stock(items, product_id, new_stock) do
    Enum.map(items, fn item ->
      if item.product.id == product_id,
        do: %{item | product: %{item.product | stock: new_stock}},
        else: item
    end)
  end
end
