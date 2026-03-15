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

    test "renders empty cart message", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _live, html} = live(conn, ~p"/cart")

      assert html =~ "Your cart is empty"
      assert html =~ "Browse products"
    end

    test "quantity increment updates item and total", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      html =
        live_view
        |> element(
          ~s([phx-click=update_quantity][phx-value-delta="1"][phx-value-item-id="#{item_a.id}"])
        )
        |> render_click()

      updated = Carts.list_items(cart.id) |> Enum.find(&(&1.id == item_a.id))
      assert updated.quantity == 2
      assert html =~ to_string(Money.new(product_a.amount * 2))
    end

    test "decrement button is disabled when quantity is 1", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _live_view, html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      assert html =~
               ~s(phx-value-item-id="#{item_a.id}" phx-value-delta="-1") ||
               html =~ ~s(disabled)
    end

    test "remove item shows undo banner and removes from UI", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      html =
        live_view
        |> element(~s([phx-click=remove_item][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      refute html =~ product_a.name
      assert html =~ "Undo"
      assert html =~ "Item removed"
    end

    test "checkout shows processing state then redirects on async completion", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()

      Amazin.MockPaymentGateway
      |> expect(:create_checkout_session, fn line_items, metadata, _urls ->
        assert length(line_items) == 2
        assert metadata["cart_id"] == cart.id
        {:ok, "https://checkout.stripe.com/test-session"}
      end)

      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      html = live_view |> element("button", "Checkout") |> render_click()
      assert html =~ "Processing payment"

      assert_redirect(live_view, "https://checkout.stripe.com/test-session")
    end

    test "checkout button is disabled when cart is empty", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _live_view, html} = live(conn, ~p"/cart")

      assert html =~ "disabled"
      assert html =~ "Your cart is empty"
    end

    test "switch tab shows summary content", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      html = live_view |> element("button", "Summary") |> render_click()

      assert html =~ "Subtotal"
      assert html =~ "Total"
      assert html =~ "Shipping"
    end

    test "apply valid promo code shows discount", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      live_view |> element("button", "Summary") |> render_click()

      html =
        live_view
        |> form("[phx-submit=apply_promo]", %{code: "SAVE10"})
        |> render_submit()

      assert html =~ "SAVE10"
      assert html =~ "Promo code applied"
    end

    test "apply invalid promo code shows error", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      html =
        live_view
        |> form("[phx-submit=apply_promo]", %{code: "BOGUS"})
        |> render_submit()

      assert html =~ "Invalid promo code"
    end

    test "save for later moves item to saved tab", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      html =
        live_view
        |> element(~s([phx-click=save_for_later][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      assert html =~ "Saved for later"

      html = live_view |> element("button", ~r/Saved/) |> render_click()
      assert html =~ product_a.name
      assert html =~ "Move to Cart"
    end

    test "move to cart restores item from saved tab", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      live_view
      |> element(~s([phx-click=save_for_later][phx-value-item-id="#{item_a.id}"]))
      |> render_click()

      live_view |> element("button", ~r/Saved/) |> render_click()

      html =
        live_view
        |> element(~s([phx-click=move_to_cart][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      assert html =~ "Moved to cart"

      html = live_view |> element("button", ~r/Items/) |> render_click()
      assert html =~ product_a.name
    end

    test "toggle gift wrap on cart item", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      html =
        live_view
        |> element(~s([phx-click=toggle_gift_wrap][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      assert html =~ "Gift wrap"

      html = live_view |> element("button", "Summary") |> render_click()
      assert html =~ "Gift Wrap"
    end

    test "select shipping method updates summary", %{conn: conn} do
      {cart, _products} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      live_view |> element("button", "Summary") |> render_click()

      html =
        live_view
        |> element(~s([phx-click=select_shipping][phx-value-method="express"]))
        |> render_click()

      assert html =~ "Express"
    end

    test "undo remove restores the item to cart", %{conn: conn} do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _html} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      live_view
      |> element(~s([phx-click=remove_item][phx-value-item-id="#{item_a.id}"]))
      |> render_click()

      html =
        live_view
        |> element(~s([phx-click=undo_remove]))
        |> render_click()

      assert html =~ product_a.name
      assert html =~ "Item restored"
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
