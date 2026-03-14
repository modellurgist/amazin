defmodule AmazinWeb.StripeWebhookHandlerTest do
  use Amazin.DataCase

  alias AmazinWeb.StripeWebhookHandler
  alias Amazin.Foundation.Carts

  import Amazin.StoreFixtures

  test "checkout.session.completed creates order and completes cart" do
    {cart, _products} = cart_with_items_fixture()

    event = %Stripe.Event{
      type: "checkout.session.completed",
      data: %{object: %{metadata: %{"cart_id" => to_string(cart.id)}}}
    }

    assert :ok = StripeWebhookHandler.handle_event(event)
    assert Carts.get(cart.id).status == :completed
  end

  test "unhandled event returns :ok" do
    event = %Stripe.Event{type: "payment_intent.succeeded", data: %{object: %{}}}
    assert :ok = StripeWebhookHandler.handle_event(event)
  end
end
