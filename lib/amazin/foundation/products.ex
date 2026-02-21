defmodule Amazin.Foundation.Products do
  @moduledoc """
  Foundation-layer persistence for products.
  Pure database operations — no broadcasting, no domain logic.
  """

  import Ecto.Query, warn: false
  alias Amazin.Repo
  alias Amazin.Foundation.Schemas.Product

  @spec list() :: [Product.t()]
  def list do
    Repo.all(Product)
  end

  @spec get!(integer()) :: Product.t()
  def get!(id), do: Repo.get!(Product, id)

  @spec insert(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(Product.t()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Product{} = product) do
    Repo.delete(product)
  end

  @spec changeset(Product.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end
end
