defmodule Amazin.StoreTest do
  use Amazin.DataCase

  alias Amazin.Store

  describe "products" do
    alias Amazin.Store.Product

    import Amazin.StoreFixtures

    @invalid_attrs %{name: nil, description: nil, amount: nil, stock: nil, thumbnail: nil}

    test "list_products/0 returns all products" do
      product = product_fixture()
      assert Store.list_products() == [product]
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Store.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product" do
      valid_attrs = %{name: "some name", description: "some description", amount: 42, stock: 42, thumbnail: "some thumbnail"}

      assert {:ok, %Product{} = product} = Store.create_product(valid_attrs)
      assert product.name == "some name"
      assert product.description == "some description"
      assert product.amount == 42
      assert product.stock == 42
      assert product.thumbnail == "some thumbnail"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Store.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()
      update_attrs = %{name: "some updated name", description: "some updated description", amount: 43, stock: 43, thumbnail: "some updated thumbnail"}

      assert {:ok, %Product{} = product} = Store.update_product(product, update_attrs)
      assert product.name == "some updated name"
      assert product.description == "some updated description"
      assert product.amount == 43
      assert product.stock == 43
      assert product.thumbnail == "some updated thumbnail"
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = Store.update_product(product, @invalid_attrs)
      assert product == Store.get_product!(product.id)
    end

    test "delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Store.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Store.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = Store.change_product(product)
    end
  end

  describe "carts" do
    alias Amazin.Store.{Cart, CartItem}

    import Amazin.StoreFixtures

    test "create_cart/0 creates an open cart" do
      assert {:ok, %Cart{status: :open}} = Store.create_cart()
    end

    test "get_cart/1 retrieves a cart by id" do
      {:ok, cart} = Store.create_cart()
      assert %Cart{status: :open} = Store.get_cart(cart.id)
    end

    test "get_cart/1 returns nil for missing cart" do
      assert Store.get_cart(-1) == nil
    end

    test "list_cart_items/1 returns items with preloaded products" do
      {cart, [product_a, _product_b]} = cart_with_items_fixture()
      items = Store.list_cart_items(cart.id)
      assert length(items) == 2
      first = Enum.find(items, &(&1.product.id == product_a.id))
      assert %CartItem{quantity: 1} = first
      assert first.product.name == "Widget"
    end

    test "add_item_to_cart/2 inserts a new item with quantity 1" do
      cart = cart_fixture()
      product = product_fixture()
      assert {:ok, %CartItem{quantity: 1}} = Store.add_item_to_cart(cart.id, product)
    end

    test "add_item_to_cart/2 increments quantity on duplicate product" do
      cart = cart_fixture()
      product = product_fixture()
      {:ok, _} = Store.add_item_to_cart(cart.id, product)
      {:ok, _} = Store.add_item_to_cart(cart.id, product)
      items = Store.list_cart_items(cart.id)
      assert [%CartItem{quantity: 2}] = items
    end
  end

  describe "orders" do
    alias Amazin.Store.Order

    import Amazin.StoreFixtures

    test "create_order/1 marks cart as completed and creates order" do
      {cart, _products} = cart_with_items_fixture()
      assert {:ok, %Order{cart_id: cart_id}} = Store.create_order(cart.id)
      assert cart_id == cart.id
      assert Store.get_cart(cart.id).status == :completed
    end
  end

  describe "pubsub" do
    import Amazin.StoreFixtures

    test "broadcasts product_created on create" do
      Store.subscribe_to_product_events()
      product = product_fixture(%{name: "PubSub Product"})
      assert_received {:product_created, ^product}
    end

    test "broadcasts product_updated on update" do
      product = product_fixture()
      Store.subscribe_to_product_events()
      {:ok, updated} = Store.update_product(product, %{name: "Updated Name"})
      assert_received {:product_updated, ^updated}
    end
  end
end
