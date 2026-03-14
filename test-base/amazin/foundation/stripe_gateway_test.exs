defmodule Amazin.Foundation.StripeGatewayTest do
  @moduledoc """
  Tests the StripeGateway's data transformation in isolation.
  The actual Stripe API call is not invoked — only the pure
  transformation from gateway-neutral line items to Stripe's
  expected parameter format is under test.
  """
  use ExUnit.Case, async: true

  alias Amazin.Foundation.StripeGateway

  describe "build_stripe_params/3" do
    test "transforms gateway-neutral line items to Stripe format" do
      line_items = [
        %{name: "Widget", description: "A widget", image_url: "w.png",
          unit_amount: 1000, currency: "usd", quantity: 2},
        %{name: "Gadget", description: "A gadget", image_url: "g.png",
          unit_amount: 2500, currency: "eur", quantity: 1}
      ]

      metadata = %{"cart_id" => "42"}
      urls = %{success_url: "http://localhost/success", cancel_url: "http://localhost/cancel"}

      params = StripeGateway.build_stripe_params(line_items, metadata, urls)

      assert params.mode == :payment
      assert params.metadata == %{"cart_id" => "42"}
      assert params.success_url == "http://localhost/success"
      assert params.cancel_url == "http://localhost/cancel"

      [first, second] = params.line_items

      assert first.quantity == 2
      assert first.price_data.currency == "usd"
      assert first.price_data.unit_amount == 1000
      assert first.price_data.product_data.name == "Widget"
      assert first.price_data.product_data.description == "A widget"
      assert first.price_data.product_data.images == ["w.png"]

      assert second.quantity == 1
      assert second.price_data.currency == "eur"
      assert second.price_data.product_data.name == "Gadget"
    end

    test "handles empty line items" do
      params = StripeGateway.build_stripe_params(
        [],
        %{},
        %{success_url: "http://x", cancel_url: "http://y"}
      )

      assert params.line_items == []
    end
  end
end
