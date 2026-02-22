defmodule AmazinWeb.StripeWebhookHandler do
  @moduledoc """
  Stripe webhook handler — thin Application-layer dispatcher.
  Translates Stripe events into Foundation persistence calls.
  """
  @behaviour Stripe.WebhookHandler

  alias Amazin.Foundation.{Orders, Carts, Products, Broadcast}

  @impl true
  def handle_event(%Stripe.Event{type: "checkout.session.completed"} = event) do
    cart_id = String.to_integer(event.data.object.metadata["cart_id"])
    Orders.create(cart_id)
    decrement_stock_for_cart(cart_id)
    :ok
  end

  @impl true
  def handle_event(_event), do: :ok

  defp decrement_stock_for_cart(cart_id) do
    Carts.list_items(cart_id)
    |> Enum.each(fn item ->
      case Products.decrement_stock(item.product.id, item.quantity) do
        {:ok, product} ->
          Broadcast.notify(:stock_changed, {item.product.id, product.stock})

        {:error, _} ->
          :ok
      end
    end)
  end
end
