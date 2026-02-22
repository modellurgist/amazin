defmodule Amazin.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub wrapper for application events.
  """

  @product_topic "products"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Amazin.PubSub, @product_topic)
  end

  @spec notify(atom(), term()) :: :ok | {:error, term()}
  def notify(event, payload) do
    Phoenix.PubSub.broadcast(Amazin.PubSub, @product_topic, {event, payload})
  end
end
