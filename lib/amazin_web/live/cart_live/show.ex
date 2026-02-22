defmodule AmazinWeb.CartLive.Show do
  @moduledoc """
  Application layer: LiveView for the shopping cart.

  This module mirrors CoffeeLive's structure: a thin execution context
  that dispatches events to a pure state machine (CartPage) and applies
  the outcomes as side effects (persist, stream, flash, redirect, async).

  Every handler follows the same shape:
    1. Parse/gather context (early from @page, late from DB)
    2. Call `dispatch/3` which delegates to `CartPage.handle/3`
    3. `dispatch` assigns the updated page and applies the outcome

  Outcomes are self-describing tagged tuples — `{:quantity_changed, item}`,
  `{:redirect, url}`, etc. — so the same `apply_outcome/2` clause handles
  an outcome regardless of which event produced it.

  The template renders from @page assigns and @streams.cart_items.
  All components are stateless function components — no LiveComponents,
  no send(self(), ...).
  """

  use AmazinWeb, :live_view

  alias Amazin.Pages.CartPage
  alias Amazin.Foundation.{Carts, Products, Broadcast}
  alias Amazin.Domain.Inventory

  @impl true
  def mount(_params, session, socket) do
    cart_id = session["cart_id"]
    items = Carts.list_items(cart_id)
    page = CartPage.new(cart_id, items)

    if connected?(socket), do: Broadcast.subscribe()

    {:ok, socket |> assign(:page, page) |> stream(:cart_items, items)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Event handlers — parse params, then dispatch to CartPage
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => delta}, socket) do
    {:noreply, dispatch(socket, :update_quantity, %{
      item_id: String.to_integer(id),
      delta: String.to_integer(delta)
    })}
  end

  def handle_event("remove_item", %{"item-id" => id}, socket) do
    {:noreply, dispatch(socket, :remove_item, %{item_id: String.to_integer(id)})}
  end

  def handle_event("checkout", _params, socket) do
    stock = Products.stock_levels(product_ids(socket.assigns.page))
    {:noreply, dispatch(socket, :checkout, %{stock_levels: stock})}
  end

  # ---------------------------------------------------------------------------
  # Async completion — dispatch back through CartPage
  # ---------------------------------------------------------------------------

  @impl true
  def handle_async(:checkout, {:ok, {:ok, url}}, socket) do
    {:noreply, dispatch(socket, :checkout_complete, %{url: url})}
  end

  def handle_async(:checkout, {:ok, {:error, reason}}, socket) do
    {:noreply, dispatch(socket, :checkout_failed, %{reason: reason})}
  end

  def handle_async(:checkout, {:exit, _reason}, socket) do
    {:noreply, dispatch(socket, :checkout_failed, %{})}
  end

  # ---------------------------------------------------------------------------
  # PubSub — external changes forwarded to CartPage
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    {:noreply, dispatch(socket, :stock_changed, %{product_id: product_id, new_stock: new_stock})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Dispatch — the uniform bridge between handlers and CartPage
  # ---------------------------------------------------------------------------

  defp dispatch(socket, event, data) do
    {page, outcome} = CartPage.handle(event, data, socket.assigns.page)
    socket |> assign(:page, page) |> apply_outcome(outcome)
  end

  # ---------------------------------------------------------------------------
  # Outcome application — self-describing: keyed on the outcome, not the event
  # ---------------------------------------------------------------------------

  defp apply_outcome(socket, {:quantity_changed, updated_item}) do
    Carts.update_quantity(socket.assigns.page.cart_id, updated_item.id, updated_item.quantity)
    stream_insert(socket, :cart_items, updated_item)
  end

  defp apply_outcome(socket, {:item_removed, item}) when not is_nil(item) do
    Carts.remove_item(socket.assigns.page.cart_id, item.id)
    stream_delete(socket, :cart_items, item)
  end

  defp apply_outcome(socket, {:item_removed, nil}), do: socket

  defp apply_outcome(socket, {:checkout_ready, line_items, metadata}) do
    start_async(socket, :checkout, fn ->
      payment_gateway().create_checkout_session(line_items, metadata, checkout_urls())
    end)
  end

  defp apply_outcome(socket, {:error, :empty_cart}) do
    put_flash(socket, :error, "Your cart is empty")
  end

  defp apply_outcome(socket, {:error, {:out_of_stock, _items}}) do
    put_flash(socket, :error, "Some items are out of stock")
  end

  defp apply_outcome(socket, {:redirect, url}) do
    redirect(socket, external: url)
  end

  defp apply_outcome(socket, {:checkout_error, msg}) do
    put_flash(socket, :error, msg)
  end

  defp apply_outcome(socket, :noop), do: socket

  # ---------------------------------------------------------------------------
  # Render — inline for locality of behavior
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-8 font-semibold">Your Cart</h1>

      <div id="cart_items" phx-update="stream">
        <.cart_item_row
          :for={{dom_id, cart_item} <- @streams.cart_items}
          id={dom_id}
          cart_item={cart_item}
        />
      </div>

      <.empty_cart_message :if={@page.items == []} />
      <.cart_total :if={@page.items != []} total={@page.total} />
      <.checkout_section status={@page.checkout_status} empty={@page.items == []} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Function components — pure functions of assigns, no domain logic
  # ---------------------------------------------------------------------------

  defp cart_item_row(assigns) do
    ~H"""
    <div
      id={@id}
      class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4"
    >
      <img
        class="w-16 h-16 object-contain"
        src={@cart_item.product.thumbnail}
        alt={@cart_item.product.name}
      />
      <div>
        <div class="font-medium"><%= @cart_item.product.name %></div>
        <div class="text-sm text-zinc-500">
          <%= Money.new(@cart_item.product.amount) %> each
        </div>
        <.stock_badge stock={@cart_item.product.stock} />
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="update_quantity"
          phx-value-item-id={@cart_item.id}
          phx-value-delta="-1"
          disabled={@cart_item.quantity <= 1}
          class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30 hover:bg-zinc-100"
        >
          -
        </button>
        <span class="w-8 text-center font-mono"><%= @cart_item.quantity %></span>
        <button
          phx-click="update_quantity"
          phx-value-item-id={@cart_item.id}
          phx-value-delta="1"
          class="w-8 h-8 rounded border text-lg font-bold hover:bg-zinc-100"
        >
          +
        </button>
      </div>
      <div class="text-right w-24">
        <div class="font-semibold">
          <%= Money.new(@cart_item.product.amount * @cart_item.quantity) %>
        </div>
        <button
          phx-click="remove_item"
          phx-value-item-id={@cart_item.id}
          class="text-xs text-red-500 hover:text-red-700"
        >
          Remove
        </button>
      </div>
    </div>
    """
  end

  defp stock_badge(assigns) do
    status = Inventory.stock_status(assigns.stock)
    assigns = assign(assigns, :status, status)

    ~H"""
    <span
      :if={@status != :in_stock}
      class={[
        "text-xs font-medium px-1.5 py-0.5 rounded",
        @status == :low_stock && "bg-amber-100 text-amber-700",
        @status == :out_of_stock && "bg-red-100 text-red-700"
      ]}
    >
      <%= if @status == :low_stock, do: "Low stock", else: "Out of stock" %>
    </span>
    """
  end

  defp empty_cart_message(assigns) do
    ~H"""
    <div class="py-12 text-center text-zinc-400">
      Your cart is empty.
      <.link navigate={~p"/products"} class="text-blue-500 hover:underline">Browse products</.link>
    </div>
    """
  end

  defp cart_total(assigns) do
    ~H"""
    <div class="flex justify-between items-center py-6 border-t-2">
      <span class="font-bold text-xl">Total</span>
      <span class="font-bold text-xl"><%= @total %></span>
    </div>
    """
  end

  defp checkout_section(assigns) do
    ~H"""
    <div class="py-4">
      <button
        :if={@status == :idle}
        phx-click="checkout"
        disabled={@empty}
        class={["phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80", @empty && "opacity-50 cursor-not-allowed"]}
      >
        Checkout
      </button>
      <div :if={@status == :processing} class="flex items-center gap-3 text-zinc-500 py-2">
        <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        Processing payment...
      </div>
      <div :if={@status == :error} class="space-y-2">
        <p class="text-red-600 text-sm">Checkout failed.</p>
        <.button phx-click="checkout">Try again</.button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp payment_gateway do
    Application.get_env(:amazin, :payment_gateway, Amazin.Foundation.StripeGateway)
  end

  defp checkout_urls, do: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}

  defp product_ids(%CartPage{items: items}) do
    Enum.map(items, & &1.product.id)
  end
end
