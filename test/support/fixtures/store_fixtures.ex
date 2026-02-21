defmodule Amazin.StoreFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Amazin.Store` context.
  """

  alias Amazin.Store

  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      attrs
      |> Enum.into(%{
        name: "some name",
        description: "some description",
        amount: 42,
        stock: 42,
        thumbnail: "some thumbnail"
      })
      |> Store.create_product()

    product
  end

  def cart_fixture do
    {:ok, cart} = Store.create_cart()
    cart
  end

  def cart_with_items_fixture do
    cart = cart_fixture()
    product_a = product_fixture(%{name: "Widget", amount: 1000, stock: 10, thumbnail: "w.png"})
    product_b = product_fixture(%{name: "Gadget", amount: 2500, stock: 5, thumbnail: "g.png"})
    {:ok, _} = Store.add_item_to_cart(cart.id, product_a)
    {:ok, _} = Store.add_item_to_cart(cart.id, product_b)
    {cart, [product_a, product_b]}
  end
end
