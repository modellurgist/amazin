defmodule Amazin.Foundation.Carts do
  @moduledoc """
  Foundation-layer persistence for carts and cart items.
  """

  import Ecto.Query, warn: false
  alias Amazin.Repo
  alias Amazin.Foundation.Schemas.{Cart, CartItem}

  @spec create() :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def create do
    Repo.insert(%Cart{status: :open})
  end

  @spec get(integer()) :: Cart.t() | nil
  def get(id) do
    Repo.get(Cart, id)
  end

  @spec list_items(integer()) :: [CartItem.t()]
  def list_items(cart_id) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id)
    |> preload(:product)
    |> Repo.all()
  end

  @spec add_item(integer(), Amazin.Foundation.Schemas.Product.t()) ::
          {:ok, CartItem.t()} | {:error, Ecto.Changeset.t()}
  def add_item(cart_id, product) do
    Repo.insert(%CartItem{cart_id: cart_id, product: product, quantity: 1},
      conflict_target: [:cart_id, :product_id],
      on_conflict: [inc: [quantity: 1]]
    )
  end

  @spec complete(Cart.t()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def complete(%Cart{} = cart) do
    cart
    |> Cart.changeset(%{status: :completed})
    |> Repo.update()
  end
end
