defmodule Amazin.Foundation.StripeGateway do
  @moduledoc """
  Stripe implementation of the PaymentGateway behaviour.
  """

  @behaviour Amazin.Foundation.PaymentGateway

  @impl true
  def create_checkout_session(line_items, metadata, urls) do
    params = build_stripe_params(line_items, metadata, urls)

    case Stripe.Checkout.Session.create(params) do
      {:ok, session} -> {:ok, session.url}
      {:error, _} = error -> error
    end
  end

  @doc false
  def build_stripe_params(line_items, metadata, urls) do
    %{
      line_items: Enum.map(line_items, &to_stripe_line_item/1),
      mode: :payment,
      success_url: urls.success_url,
      cancel_url: urls.cancel_url,
      metadata: metadata
    }
  end

  defp to_stripe_line_item(item) do
    %{
      price_data: %{
        currency: item.currency,
        product_data: %{
          name: item.name,
          description: item.description,
          images: [item.image_url]
        },
        unit_amount: item.unit_amount
      },
      quantity: item.quantity
    }
  end
end
