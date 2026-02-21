defmodule AmazinWeb.CartLiveTest do
  use AmazinWeb.ConnCase

  import Phoenix.LiveViewTest
  import Amazin.StoreFixtures
  import Mox

  alias Amazin.Foundation.Carts

  setup :verify_on_exit!

  describe "CartLive.Show" do
    test "renders cart items and total", %{conn: conn} do
      {cart, [product_a, product_b]} = cart_with_items_fixture()

      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _live, html} = live(conn, ~p"/cart")

      assert html =~ "Your Cart"
      assert html =~ product_a.name
      assert html =~ product_b.name
      assert html =~ "Checkout"
    end

    test "renders empty cart", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _live, html} = live(conn, ~p"/cart")

      assert html =~ "Your Cart"
    end

    test "checkout redirects to payment gateway URL", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()

      Amazin.MockPaymentGateway
      |> expect(:create_checkout_session, fn line_items, metadata, _urls ->
        assert length(line_items) == 2
        assert metadata["cart_id"] == cart.id
        {:ok, "https://checkout.stripe.com/test-session"}
      end)

      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      assert {:error, {:redirect, %{to: "https://checkout.stripe.com/test-session"}}} =
               live_view |> element("button", "Checkout") |> render_click()
    end
  end

  describe "CartLive.Success" do
    test "renders success message", %{conn: conn} do
      {:ok, cart} = Carts.create()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _live, html} = live(conn, ~p"/cart/success")

      assert html =~ "You did it!"
      assert html =~ "Thanks for your business!"
    end
  end
end
