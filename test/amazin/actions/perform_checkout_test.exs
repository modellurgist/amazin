defmodule Amazin.Actions.PerformCheckoutTest do
  use Amazin.DataCase

  import Amazin.StoreFixtures
  import Mox

  alias Amazin.Actions.PerformCheckout

  setup :verify_on_exit!

  @urls %{success_url: "http://localhost/cart/success", cancel_url: "http://localhost/cart"}

  describe "run/3" do
    test "returns checkout URL when cart has items" do
      {cart, _products} = cart_with_items_fixture()

      Amazin.MockPaymentGateway
      |> expect(:create_checkout_session, fn line_items, metadata, urls ->
        assert length(line_items) == 2
        assert metadata["cart_id"] == cart.id
        assert urls.success_url == "http://localhost/cart/success"
        {:ok, "https://checkout.stripe.com/sess_123"}
      end)

      assert {:ok, "https://checkout.stripe.com/sess_123"} =
               PerformCheckout.run(cart.id, Amazin.MockPaymentGateway, @urls)
    end

    test "returns error when cart is empty" do
      cart = cart_fixture()

      assert {:error, :empty_cart} =
               PerformCheckout.run(cart.id, Amazin.MockPaymentGateway, @urls)
    end

    test "returns error when payment gateway fails" do
      {cart, _products} = cart_with_items_fixture()

      Amazin.MockPaymentGateway
      |> expect(:create_checkout_session, fn _items, _meta, _urls ->
        {:error, :gateway_unavailable}
      end)

      assert {:error, :gateway_unavailable} =
               PerformCheckout.run(cart.id, Amazin.MockPaymentGateway, @urls)
    end
  end
end
