defmodule AmazinWeb.CartLive.Show do
  use AmazinWeb, :live_view

  alias Amazin.Foundation.Carts
  alias Amazin.Domain.Pricing
  alias Amazin.Actions.PerformCheckout

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
    result = PerformCheckout.run(socket.assigns.cart_id, payment_gateway(), checkout_urls())
    {:noreply, apply_checkout(socket, result)}
  end

  defp apply_checkout(socket, {:ok, url}), do: redirect(socket, external: url)
  defp apply_checkout(socket, {:error, :empty_cart}), do: put_flash(socket, :error, "Your cart is empty")
  defp apply_checkout(socket, {:error, _}), do: put_flash(socket, :error, "Checkout failed")

  defp payment_gateway do
    Application.get_env(:amazin, :payment_gateway, Amazin.Foundation.StripeGateway)
  end

  defp checkout_urls, do: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}
end
