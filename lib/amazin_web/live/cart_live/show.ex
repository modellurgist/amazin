defmodule AmazinWeb.CartLive.Show do
  @moduledoc """
  Thin LiveView shell for the cart page.
  Dispatches events to CartPage, then interprets the returned outcomes.
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

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => delta}, socket) do
    {:noreply,
     dispatch(socket, :update_quantity, %{
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

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, dispatch(socket, :switch_tab, %{tab: String.to_existing_atom(tab)})}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    {:noreply, dispatch(socket, :apply_promo, %{code: code})}
  end

  # ── Async ─────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:checkout, {:ok, {:ok, url}}, socket) do
    {:noreply, dispatch(socket, :checkout_complete, %{url: url})}
  end

  def handle_async(:checkout, {:ok, {:error, _reason}}, socket) do
    {:noreply, dispatch(socket, :checkout_failed, %{})}
  end

  def handle_async(:checkout, {:exit, _reason}, socket) do
    {:noreply, dispatch(socket, :checkout_failed, %{})}
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    {:noreply,
     dispatch(socket, :stock_changed, %{product_id: product_id, new_stock: new_stock})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Dispatch & Outcome Interpreter ────────────────────────────────────

  defp dispatch(socket, event, data) do
    {page, outcomes} = CartPage.handle(event, data, socket.assigns.page)
    socket |> assign(:page, page) |> apply_outcomes(outcomes)
  end

  defp apply_outcomes(socket, outcomes) do
    Enum.reduce(outcomes, socket, &apply_outcome(&2, &1))
  end

  defp apply_outcome(socket, :noop), do: socket
  defp apply_outcome(socket, {:flash, level, msg}), do: put_flash(socket, level, msg)
  defp apply_outcome(socket, {:redirect, url}), do: redirect(socket, external: url)
  defp apply_outcome(socket, {:stream_insert, col, item}), do: stream_insert(socket, col, item)
  defp apply_outcome(socket, {:stream_delete, col, item}), do: stream_delete(socket, col, item)

  defp apply_outcome(socket, {:stream_reset, col, items}) do
    stream(socket, col, items, reset: true)
  end

  defp apply_outcome(socket, {:push_event, event, payload}) do
    push_event(socket, event, payload)
  end

  defp apply_outcome(socket, {:persist_quantity, cart_id, item_id, qty}) do
    Carts.update_quantity(cart_id, item_id, qty)
    socket
  end

  defp apply_outcome(socket, {:persist_remove, cart_id, item_id}) do
    Carts.remove_item(cart_id, item_id)
    socket
  end

  defp apply_outcome(socket, {:start_checkout, line_items, metadata}) do
    start_async(socket, :checkout, fn ->
      payment_gateway().create_checkout_session(line_items, metadata, checkout_urls())
    end)
  end

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={tab <- [:items, :summary]}
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "px-4 py-2 text-sm font-medium rounded-t",
            if(@page.ui.active_tab == tab,
              do: "bg-zinc-900 text-white",
              else: "text-zinc-500 hover:text-zinc-700"
            )
          ]}
        >
          <%= Phoenix.Naming.humanize(tab) %>
        </button>
      </nav>

      <div :if={@page.ui.active_tab == :items}>
        <div id="cart_items" phx-update="stream">
          <.cart_item_row
            :for={{dom_id, cart_item} <- @streams.cart_items}
            id={dom_id}
            cart_item={cart_item}
          />
        </div>
        <.empty_cart_message :if={@page.domain.items == []} />
      </div>

      <div :if={@page.ui.active_tab == :summary}>
        <.cart_summary
          subtotal={@page.domain.subtotal}
          discount={@page.domain.discount}
          total={@page.domain.total}
          item_count={@page.domain.item_count}
          promo_code={@page.domain.promo_code}
        />
      </div>

      <.promo_form error={@page.ui.promo_error} current_code={@page.domain.promo_code} />
      <.checkout_section status={@page.checkout_status} empty={@page.domain.items == []} />
    </div>
    """
  end

  # ── Function Components ───────────────────────────────────────────────

  defp cart_item_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img
        class="w-16 h-16 object-contain"
        src={@cart_item.product.thumbnail}
        alt={@cart_item.product.name}
      />
      <div>
        <div class="font-medium"><%= @cart_item.product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@cart_item.product.amount) %> each</div>
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

  defp cart_summary(assigns) do
    ~H"""
    <div class="space-y-3 py-6">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span><%= @item_count %></span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span><%= @subtotal %></span>
      </div>
      <div :if={@promo_code} class="flex justify-between text-green-600">
        <span>Discount (<%= @promo_code %>)</span><span>-<%= @discount %></span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>Total</span><span><%= @total %></span>
      </div>
    </div>
    """
  end

  defp promo_form(assigns) do
    ~H"""
    <form phx-submit="apply_promo" class="flex gap-2 py-4">
      <input
        type="text"
        name="code"
        placeholder="Promo code"
        value={@current_code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button
        type="submit"
        class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium hover:bg-zinc-300"
      >
        Apply
      </button>
      <span :if={@error} class="text-red-500 text-sm self-center"><%= @error %></span>
    </form>
    """
  end

  defp checkout_section(assigns) do
    ~H"""
    <div class="py-4">
      <button
        :if={@status == :idle}
        phx-click="checkout"
        disabled={@empty}
        class={[
          "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700",
          "py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80",
          @empty && "opacity-50 cursor-not-allowed"
        ]}
      >
        Checkout
      </button>
      <div :if={@status == :processing} class="flex items-center gap-3 text-zinc-500 py-2">
        <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"
          />
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
        Processing payment...
      </div>
      <div :if={@status == :error} class="space-y-2">
        <p class="text-red-600 text-sm">Checkout failed.</p>
        <button
          phx-click="checkout"
          class="rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white"
        >
          Try again
        </button>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp payment_gateway do
    Application.get_env(:amazin, :payment_gateway, Amazin.Foundation.StripeGateway)
  end

  defp checkout_urls do
    %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}
  end

  defp product_ids(%CartPage{domain: %{items: items}}) do
    Enum.map(items, & &1.product.id)
  end
end
