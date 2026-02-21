defmodule Amazin.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub wrapper for product events.
  """

  @topic "products"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Amazin.PubSub, @topic)
  end

  @spec notify(atom(), term()) :: :ok | {:error, term()}
  def notify(event, payload) do
    Phoenix.PubSub.broadcast(Amazin.PubSub, @topic, {event, payload})
  end
end
