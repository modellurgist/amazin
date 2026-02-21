defmodule Amazin.Foundation.ProductsTest do
  use Amazin.DataCase

  alias Amazin.Foundation.Products
  alias Amazin.Foundation.Schemas.Product

  import Amazin.StoreFixtures

  @invalid_attrs %{name: nil, description: nil, amount: nil, stock: nil, thumbnail: nil}

  test "list/0 returns all products" do
    product = product_fixture()
    assert Products.list() == [product]
  end

  test "get!/1 returns the product with given id" do
    product = product_fixture()
    assert Products.get!(product.id) == product
  end

  test "insert/1 with valid data creates a product" do
    valid_attrs = %{name: "some name", description: "some description", amount: 42, stock: 42, thumbnail: "some thumbnail"}

    assert {:ok, %Product{} = product} = Products.insert(valid_attrs)
    assert product.name == "some name"
    assert product.description == "some description"
    assert product.amount == 42
  end

  test "insert/1 with invalid data returns error changeset" do
    assert {:error, %Ecto.Changeset{}} = Products.insert(@invalid_attrs)
  end

  test "update/2 with valid data updates the product" do
    product = product_fixture()
    assert {:ok, %Product{} = updated} = Products.update(product, %{name: "updated"})
    assert updated.name == "updated"
  end

  test "update/2 with invalid data returns error changeset" do
    product = product_fixture()
    assert {:error, %Ecto.Changeset{}} = Products.update(product, @invalid_attrs)
    assert product == Products.get!(product.id)
  end

  test "delete/1 deletes the product" do
    product = product_fixture()
    assert {:ok, %Product{}} = Products.delete(product)
    assert_raise Ecto.NoResultsError, fn -> Products.get!(product.id) end
  end

  test "changeset/1 returns a product changeset" do
    product = product_fixture()
    assert %Ecto.Changeset{} = Products.changeset(product)
  end
end

defmodule Amazin.Foundation.CartsTest do
  use Amazin.DataCase

  alias Amazin.Foundation.Carts
  alias Amazin.Foundation.Schemas.{Cart, CartItem}

  import Amazin.StoreFixtures

  test "create/0 creates an open cart" do
    assert {:ok, %Cart{status: :open}} = Carts.create()
  end

  test "get/1 retrieves a cart by id" do
    {:ok, cart} = Carts.create()
    assert %Cart{status: :open} = Carts.get(cart.id)
  end

  test "get/1 returns nil for missing cart" do
    assert Carts.get(-1) == nil
  end

  test "list_items/1 returns items with preloaded products" do
    {cart, [product_a, _product_b]} = cart_with_items_fixture()
    items = Carts.list_items(cart.id)
    assert length(items) == 2
    first = Enum.find(items, &(&1.product.id == product_a.id))
    assert %CartItem{quantity: 1} = first
    assert first.product.name == "Widget"
  end

  test "add_item/2 inserts a new item with quantity 1" do
    cart = cart_fixture()
    product = product_fixture()
    assert {:ok, %CartItem{quantity: 1}} = Carts.add_item(cart.id, product)
  end

  test "add_item/2 increments quantity on duplicate product" do
    cart = cart_fixture()
    product = product_fixture()
    {:ok, _} = Carts.add_item(cart.id, product)
    {:ok, _} = Carts.add_item(cart.id, product)
    items = Carts.list_items(cart.id)
    assert [%CartItem{quantity: 2}] = items
  end

  test "complete/1 marks a cart as completed" do
    {:ok, cart} = Carts.create()
    assert {:ok, %Cart{status: :completed}} = Carts.complete(cart)
  end
end

defmodule Amazin.Foundation.OrdersTest do
  use Amazin.DataCase

  alias Amazin.Foundation.{Orders, Carts}
  alias Amazin.Foundation.Schemas.Order

  import Amazin.StoreFixtures

  test "create/1 marks cart as completed and creates order" do
    {cart, _products} = cart_with_items_fixture()
    assert {:ok, %Order{cart_id: cart_id}} = Orders.create(cart.id)
    assert cart_id == cart.id
    assert Carts.get(cart.id).status == :completed
  end
end

defmodule Amazin.Foundation.BroadcastTest do
  use Amazin.DataCase

  alias Amazin.Foundation.{Products, Broadcast}

  import Amazin.StoreFixtures

  test "subscribe and receive notifications" do
    Broadcast.subscribe()
    product = product_fixture()
    Broadcast.notify(:product_created, product)
    assert_received {:product_created, ^product}
  end
end
