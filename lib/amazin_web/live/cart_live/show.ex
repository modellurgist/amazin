defmodule AmazinWeb.CartLive.Show do
  @moduledoc """
  V20 Interceptor Pipeline LiveView shell.

  Every event has a declared pipeline of interceptor modules.
  The pipeline executes enter phases left-to-right, then leave
  phases right-to-left, producing a final Context with updated
  domain/UI state and a list of outcomes.

  Cross-cutting concerns (signal routing, stock injection) are
  reusable interceptors — the LiveView only declares pipelines
  and applies outcomes.
  """

  use AmazinWeb, :live_view

  alias Amazin.Interceptor
  alias Amazin.Interceptor.Context
  alias Amazin.Interceptors.{DomainDispatch, UIDispatch, SignalRouter, InjectStock}
  alias Amazin.Domain.CartDomain
  alias Amazin.UI.CartUI
  alias Amazin.Foundation.{Carts, Broadcast}
  alias Amazin.Domain.{Inventory, Shipping}

  # ── Pipeline Declarations ────────────────────────────────────────────

  @domain_signals [DomainDispatch, SignalRouter]
  @full [DomainDispatch, UIDispatch, SignalRouter]

  @pipelines %{
    update_quantity: @domain_signals,
    remove_item: @domain_signals,
    save_for_later: @domain_signals,
    move_to_cart: @domain_signals,
    toggle_gift_wrap: [DomainDispatch],
    select_shipping: @domain_signals,
    undo_remove: @domain_signals,
    undo_expired: [DomainDispatch],
    checkout: [InjectStock, DomainDispatch, SignalRouter],
    checkout_complete: [DomainDispatch],
    checkout_failed: [DomainDispatch],
    apply_promo: @full,
    switch_tab: [UIDispatch],
    stock_changed: [DomainDispatch]
  }

  # ── Lifecycle ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, session, socket) do
    cart_id = session["cart_id"]
    items = Carts.list_items(cart_id)
    domain = CartDomain.new(cart_id, items)
    ui = CartUI.new()

    if connected?(socket), do: Broadcast.subscribe()

    {:ok,
     socket
     |> assign(:ui, ui)
     |> assign(:domain, domain)
     |> assign(:undo_timer_ref, nil)
     |> stream(:cart_items, items)
     |> stream(:saved_items, [])}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ── Events ───────────────────────────────────────────────────────────

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
    {:noreply, dispatch(socket, :checkout, %{})}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, dispatch(socket, :switch_tab, %{tab: String.to_existing_atom(tab)})}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    valid = match?({:ok, _}, Amazin.Domain.Pricing.validate_promo(code))
    {:noreply, dispatch(socket, :apply_promo, %{code: code, valid: valid})}
  end

  def handle_event("save_for_later", %{"item-id" => id}, socket) do
    {:noreply, dispatch(socket, :save_for_later, %{item_id: String.to_integer(id)})}
  end

  def handle_event("move_to_cart", %{"item-id" => id}, socket) do
    {:noreply, dispatch(socket, :move_to_cart, %{item_id: String.to_integer(id)})}
  end

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, socket) do
    {:noreply, dispatch(socket, :toggle_gift_wrap, %{item_id: String.to_integer(id)})}
  end

  def handle_event("select_shipping", %{"method" => method}, socket) do
    {:noreply, dispatch(socket, :select_shipping, %{method: String.to_existing_atom(method)})}
  end

  def handle_event("undo_remove", _params, socket) do
    {:noreply, dispatch(socket, :undo_remove, %{})}
  end

  # ── Async ────────────────────────────────────────────────────────────

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

  # ── PubSub ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    {:noreply,
     dispatch(socket, :stock_changed, %{product_id: product_id, new_stock: new_stock})}
  end

  def handle_info({:undo_expired, _item_id}, socket) do
    {:noreply, dispatch(socket, :undo_expired, %{})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Pipeline Dispatch ────────────────────────────────────────────────

  defp dispatch(socket, event, data) do
    ctx =
      Interceptor.execute(
        pipeline(event),
        %Context{
          event: event,
          data: data,
          domain: socket.assigns.domain,
          ui: socket.assigns.ui
        }
      )

    socket
    |> assign(:domain, ctx.domain)
    |> assign(:ui, ctx.ui)
    |> apply_outcomes(ctx.outcomes)
  end

  defp pipeline(event), do: Map.get(@pipelines, event, @domain_signals)

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

  defp apply_outcome(socket, {:start_undo_timer, item_id}) do
    if ref = socket.assigns[:undo_timer_ref], do: Process.cancel_timer(ref)
    ref = Process.send_after(self(), {:undo_expired, item_id}, 5000)
    assign(socket, :undo_timer_ref, ref)
  end

  defp apply_outcome(socket, :cancel_undo_timer) do
    if ref = socket.assigns[:undo_timer_ref], do: Process.cancel_timer(ref)
    assign(socket, :undo_timer_ref, nil)
  end

  # ── Render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <.undo_banner :if={@domain.pending_undo} />

      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={tab <- [:items, :summary, :saved]}
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "px-4 py-2 text-sm font-medium rounded-t",
            if(@ui.active_tab == tab,
              do: "bg-zinc-900 text-white",
              else: "text-zinc-500 hover:text-zinc-700"
            )
          ]}
        >
          <%= tab_label(tab, @domain) %>
        </button>
      </nav>

      <div class={@ui.active_tab != :items && "hidden"}>
        <div id="cart_items" phx-update="stream">
          <.cart_item_row
            :for={{dom_id, cart_item} <- @streams.cart_items}
            id={dom_id}
            cart_item={cart_item}
            gift_wrapped={MapSet.member?(@domain.gift_wrapped_ids, cart_item.id)}
          />
        </div>
        <.empty_cart_message :if={@domain.items == []} />
      </div>

      <div :if={@ui.active_tab == :summary}>
        <.cart_summary
          subtotal={@domain.subtotal}
          discount={@domain.discount}
          gift_wrap_total={@domain.gift_wrap_total}
          shipping_cost={@domain.shipping_cost}
          shipping_method={@domain.shipping_method}
          total={@domain.total}
          item_count={@domain.item_count}
          promo_code={@domain.promo_code}
        />
        <.shipping_selector method={@domain.shipping_method} subtotal={@domain.subtotal} />
      </div>

      <div class={@ui.active_tab != :saved && "hidden"}>
        <div id="saved_items" phx-update="stream">
          <.saved_item_row
            :for={{dom_id, saved_item} <- @streams.saved_items}
            id={dom_id}
            saved_item={saved_item}
          />
        </div>
        <div
          :if={@domain.saved_items == []}
          class="py-12 text-center text-zinc-400"
        >
          No saved items.
        </div>
      </div>

      <.promo_form error={@ui.promo_error} current_code={@domain.promo_code} />
      <.checkout_section status={@domain.checkout_status} empty={@domain.items == []} />
    </div>
    """
  end

  # ── Function Components ──────────────────────────────────────────────

  defp undo_banner(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4">
      <span class="text-sm text-amber-800">Item removed.</span>
      <button
        phx-click="undo_remove"
        class="text-sm font-semibold text-amber-700 hover:text-amber-900 underline"
      >
        Undo
      </button>
    </div>
    """
  end

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
        <div class="flex items-center gap-3 mt-1">
          <label class="flex items-center gap-1.5 text-xs text-zinc-500 cursor-pointer">
            <input
              type="checkbox"
              checked={@gift_wrapped}
              phx-click="toggle_gift_wrap"
              phx-value-item-id={@cart_item.id}
              class="rounded border-zinc-300 text-zinc-900 focus:ring-zinc-500"
            />
            Gift wrap ($2.99)
          </label>
          <button
            phx-click="save_for_later"
            phx-value-item-id={@cart_item.id}
            class="text-xs text-blue-500 hover:text-blue-700"
          >
            Save for Later
          </button>
        </div>
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

  defp saved_item_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto] items-center gap-4 border-b py-4">
      <img
        class="w-16 h-16 object-contain"
        src={@saved_item.product.thumbnail}
        alt={@saved_item.product.name}
      />
      <div>
        <div class="font-medium"><%= @saved_item.product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@saved_item.product.amount) %> each</div>
      </div>
      <button
        phx-click="move_to_cart"
        phx-value-item-id={@saved_item.id}
        class="text-sm font-medium text-blue-600 hover:text-blue-800"
      >
        Move to Cart
      </button>
    </div>
    """
  end

  defp shipping_selector(assigns) do
    ~H"""
    <div class="py-4">
      <h3 class="text-sm font-semibold text-zinc-700 mb-3">Shipping Method</h3>
      <div class="space-y-2">
        <label
          :for={method <- Shipping.method_names()}
          class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:bg-zinc-50"
        >
          <input
            type="radio"
            name="shipping_method"
            value={method}
            checked={@method == method}
            phx-click="select_shipping"
            phx-value-method={method}
            class="text-zinc-900 focus:ring-zinc-500"
          />
          <div class="flex-1">
            <span class="text-sm font-medium"><%= Shipping.label(method) %></span>
          </div>
          <span class="text-sm text-zinc-500">
            <%= shipping_price_label(method, @subtotal) %>
          </span>
        </label>
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
      <div :if={Money.positive?(@gift_wrap_total)} class="flex justify-between text-zinc-600">
        <span>Gift Wrap</span><span><%= @gift_wrap_total %></span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping (<%= Shipping.label(@shipping_method) %>)</span>
        <span><%= if Money.zero?(@shipping_cost), do: "Free", else: @shipping_cost %></span>
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

  # ── Helpers ──────────────────────────────────────────────────────────

  defp tab_label(:items, domain), do: "Items (#{domain.item_count})"
  defp tab_label(:summary, _domain), do: "Summary"
  defp tab_label(:saved, domain), do: "Saved (#{length(domain.saved_items)})"

  defp shipping_price_label(method, subtotal) do
    cost = Shipping.calculate(method, subtotal.amount)
    if cost == 0, do: "Free", else: Money.new(cost)
  end

  defp payment_gateway do
    Application.get_env(:amazin, :payment_gateway, Amazin.Foundation.StripeGateway)
  end

  defp checkout_urls do
    %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}
  end
end
