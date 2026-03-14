ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Amazin.Repo, :manual)

Mox.defmock(Amazin.MockPaymentGateway, for: Amazin.Foundation.PaymentGateway)
Application.put_env(:amazin, :payment_gateway, Amazin.MockPaymentGateway)
