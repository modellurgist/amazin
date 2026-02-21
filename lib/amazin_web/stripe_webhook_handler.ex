defmodule AmazinWeb.StripeWebhookHandler do
  @moduledoc """
  Stripe webhook handler — thin Application-layer dispatcher.
  Translates Stripe events into Foundation persistence calls.
  """
  @behaviour Stripe.WebhookHandler

  alias Amazin.Foundation.Orders

  @impl true
  def handle_event(%Stripe.Event{type: "checkout.session.completed"} = event) do
    cart_id = String.to_integer(event.data.object.metadata["cart_id"])
    Orders.create(cart_id)
    :ok
  end

  @impl true
  def handle_event(_event), do: :ok
end
