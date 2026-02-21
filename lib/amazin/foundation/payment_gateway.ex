defmodule Amazin.Foundation.PaymentGateway do
  @moduledoc """
  Foundation-layer behaviour for payment processing.
  Implementations wrap specific providers (Stripe, etc.).
  """

  @type line_item :: %{
          name: String.t(),
          description: String.t(),
          image_url: String.t(),
          unit_amount: integer(),
          currency: String.t(),
          quantity: integer()
        }

  @type urls :: %{success_url: String.t(), cancel_url: String.t()}

  @callback create_checkout_session([line_item()], map(), urls()) ::
              {:ok, String.t()} | {:error, term()}
end
