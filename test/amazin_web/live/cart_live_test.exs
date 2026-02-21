defmodule AmazinWeb.CartLiveTest do
  use AmazinWeb.ConnCase

  import Phoenix.LiveViewTest
  import Amazin.StoreFixtures

  alias Amazin.Store

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
  end

  describe "CartLive.Success" do
    test "renders success message", %{conn: conn} do
      {:ok, cart} = Store.create_cart()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _live, html} = live(conn, ~p"/cart/success")

      assert html =~ "You did it!"
      assert html =~ "Thanks for your business!"
    end
  end
end
