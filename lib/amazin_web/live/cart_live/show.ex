defmodule AmazinWeb.CartLive.Show do
  use AmazinWeb, :live_view

  alias Amazin.Foundation.Carts
  alias Amazin.Domain.{Pricing, Checkout}

  @impl true
  def mount(_params, session, socket) do
    cart_id = session["cart_id"]
    cart_items = Carts.list_items(cart_id)

    socket =
      socket
      |> assign(:cart_id, cart_id)
      |> assign(:total, Pricing.cart_total(cart_items))
      |> stream(:cart_items, cart_items)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("checkout", _params, socket) do
    cart_items = Carts.list_items(socket.assigns.cart_id)

    case Checkout.validate(cart_items) do
      {:ok, items} ->
        line_items = Checkout.prepare_line_items(items)
        metadata = %{"cart_id" => socket.assigns.cart_id}
        urls = %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}

        {:ok, checkout_url} = payment_gateway().create_checkout_session(line_items, metadata, urls)
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, :empty_cart} ->
        {:noreply, put_flash(socket, :error, "Your cart is empty")}
    end
  end

  defp payment_gateway do
    Application.get_env(:amazin, :payment_gateway, Amazin.Foundation.StripeGateway)
  end
end
