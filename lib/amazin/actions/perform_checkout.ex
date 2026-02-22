defmodule Amazin.Actions.PerformCheckout do
  @moduledoc """
  Application-layer action: orchestrates the checkout workflow.

  Coordinates Foundation persistence and Domain abstractions into a
  single call that returns a domain result. The LiveView maps the
  result to socket effects — it never orchestrates the steps itself.

  This is the CRUD equivalent of CoffeeMaker.do_cycle: one call in,
  one result out, all multi-step coordination encapsulated.
  """

  alias Amazin.Foundation.Carts
  alias Amazin.Domain.Checkout

  @type urls :: %{success_url: String.t(), cancel_url: String.t()}

  @spec run(integer(), module(), urls()) ::
          {:ok, String.t()} | {:error, :empty_cart | term()}
  def run(cart_id, payment_gateway, urls) do
    with items when items != [] <- Carts.list_items(cart_id),
         line_items = Checkout.prepare_line_items(items),
         metadata = %{"cart_id" => cart_id},
         {:ok, checkout_url} <- payment_gateway.create_checkout_session(line_items, metadata, urls) do
      {:ok, checkout_url}
    else
      [] -> {:error, :empty_cart}
      {:error, _} = error -> error
    end
  end
end
