defmodule AmazinWeb.Plugs.SessionCartTest do
  use AmazinWeb.ConnCase

  alias Amazin.Store

  test "creates a new cart when session has no cart_id", %{conn: conn} do
    conn = get(conn, ~p"/products")
    cart_id = get_session(conn, :cart_id)
    assert cart_id != nil
    assert %{status: :open} = Store.get_cart(cart_id)
  end

  test "reuses existing open cart", %{conn: conn} do
    {:ok, cart} = Store.create_cart()

    conn =
      conn
      |> init_test_session(%{cart_id: cart.id})
      |> get(~p"/products")

    assert get_session(conn, :cart_id) == cart.id
  end

  test "creates new cart when existing cart is completed", %{conn: conn} do
    {:ok, cart} = Store.create_cart()
    Store.create_order(cart.id)

    conn =
      conn
      |> init_test_session(%{cart_id: cart.id})
      |> get(~p"/products")

    new_cart_id = get_session(conn, :cart_id)
    assert new_cart_id != cart.id
    assert %{status: :open} = Store.get_cart(new_cart_id)
  end
end
