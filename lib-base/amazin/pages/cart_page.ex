defmodule Amazin.Pages.CartPage do
  @moduledoc """
  Application-layer page state machine for the shopping cart.

  Like CoffeeMaker for the coffee machine, CartPage holds ALL the cart
  page's working state and processes events as pure functions returning
  `{new_page, outcome}`.

  ## ALA layering

  CartPage is an Application-layer module. It orchestrates Domain
  abstractions (Pricing, Checkout, Inventory) the same way CoffeeMaker
  orchestrates Boiler, WarmerPlate, and UserInterface. It never calls
  Foundation persistence or Phoenix — the LiveView handles those as
  side effects based on the outcomes.

  ## Outcomes (Guideline 24)

  `handle/3` returns `{new_page, outcomes}` where outcomes is either a
  single tagged tuple or a list of them. The LiveView's `dispatch/3`
  uses `List.wrap` to normalize and folds them through `apply_outcome/2`.

  Generic outcomes (reusable across any Page):
  - `{:flash, level, message}`
  - `{:redirect, url}`
  - `:noop`

  Domain-specific outcomes (cart-specific applicators):
  - `{:quantity_changed, item}`
  - `{:item_removed, item}`
  - `{:checkout_ready, line_items, metadata}`

  ## Loading tiers

  - **Early (struct fields):** `items`, `total`, `checkout_status` —
    session-owned state loaded on mount, updated in-memory on events.
  - **Late (data argument):** `stock_levels` for checkout — fresh
    external data gathered by the LiveView before calling handle/3.
  - **Pushed (PubSub forwarded):** `:stock_changed` — external changes
    the LiveView receives and forwards to handle/3.
  """

  alias Amazin.Domain.{Pricing, Checkout, Inventory}

  defstruct [:cart_id, :items, :total, checkout_status: :idle]

  @type t :: %__MODULE__{
          cart_id: integer(),
          items: list(),
          total: Money.t(),
          checkout_status: :idle | :processing | :complete | :error
        }

  @spec new(integer(), list()) :: t()
  def new(cart_id, items) do
    %__MODULE__{
      cart_id: cart_id,
      items: items,
      total: Pricing.cart_total(items)
    }
  end

  # -- Quantity adjustment (early-loaded state only) --------------------------

  @type outcome :: term()
  @spec handle(atom(), map(), t()) :: {t(), outcome() | [outcome()]}

  def handle(:update_quantity, %{item_id: item_id, delta: delta}, page) do
    items = update_item_quantity(page.items, item_id, delta)
    updated_item = Enum.find(items, &(&1.id == item_id))

    {%{page | items: items, total: Pricing.cart_total(items)},
     {:quantity_changed, updated_item}}
  end

  def handle(:remove_item, %{item_id: item_id}, page) do
    {removed, remaining} = pop_item(page.items, item_id)

    {%{page | items: remaining, total: Pricing.cart_total(remaining)},
     {:item_removed, removed}}
  end

  # -- Checkout (late-loaded stock_levels) ------------------------------------

  def handle(:checkout, %{stock_levels: stock}, page) do
    case Checkout.validate(page.items) do
      {:ok, items} ->
        case Inventory.check_availability(items, stock) do
          :ok ->
            line_items = Checkout.prepare_line_items(items)
            metadata = %{"cart_id" => page.cart_id}

            {%{page | checkout_status: :processing},
             [{:checkout_ready, line_items, metadata},
              {:flash, :info, "Processing payment..."}]}

          {:error, _unavailable} ->
            {page, [{:flash, :error, "Some items are out of stock"}]}
        end

      {:error, :empty_cart} ->
        {page, [{:flash, :error, "Your cart is empty"}]}
    end
  end

  # -- Async completion (dispatched from handle_async) ------------------------

  def handle(:checkout_complete, %{url: url}, page) do
    {%{page | checkout_status: :complete}, {:redirect, url}}
  end

  def handle(:checkout_failed, _data, page) do
    {%{page | checkout_status: :error},
     [{:flash, :error, "Checkout failed. Please try again."}]}
  end

  # -- PubSub: external stock change ------------------------------------------

  def handle(:stock_changed, %{product_id: pid, new_stock: stock}, page) do
    items = update_product_stock(page.items, pid, stock)
    {%{page | items: items}, :noop}
  end

  # -- Pure helpers -----------------------------------------------------------

  defp update_item_quantity(items, item_id, delta) do
    Enum.map(items, fn item ->
      if item.id == item_id do
        %{item | quantity: max(1, item.quantity + delta)}
      else
        item
      end
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
      if item.product.id == product_id do
        %{item | product: %{item.product | stock: new_stock}}
      else
        item
      end
    end)
  end
end
