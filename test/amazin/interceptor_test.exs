defmodule Amazin.InterceptorTest do
  use ExUnit.Case, async: true

  alias Amazin.Interceptor
  alias Amazin.Interceptor.Context
  alias Amazin.Interceptors.{DomainDispatch, UIDispatch, SignalRouter}
  alias Amazin.Domain.CartDomain
  alias Amazin.UI.CartUI

  # ── Test interceptors for ordering verification ──────────────────────

  defmodule FirstTracker do
    use Amazin.Interceptor

    @impl true
    def enter(ctx) do
      %{ctx | data: Map.update(ctx.data, :log, [:first_enter], &(&1 ++ [:first_enter]))}
    end

    @impl true
    def leave(ctx) do
      %{ctx | data: Map.update(ctx.data, :log, [:first_leave], &(&1 ++ [:first_leave]))}
    end
  end

  defmodule SecondTracker do
    use Amazin.Interceptor

    @impl true
    def enter(ctx) do
      %{ctx | data: Map.update(ctx.data, :log, [:second_enter], &(&1 ++ [:second_enter]))}
    end

    @impl true
    def leave(ctx) do
      %{ctx | data: Map.update(ctx.data, :log, [:second_leave], &(&1 ++ [:second_leave]))}
    end
  end

  # ── Fixtures ─────────────────────────────────────────────────────────

  defp make_product(overrides \\ %{}) do
    Map.merge(
      %{id: 1, name: "Widget", description: "A widget", amount: 1000, stock: 10, thumbnail: "w.png"},
      overrides
    )
  end

  defp make_item(overrides) do
    Map.merge(%{id: 1, quantity: 2, product: make_product()}, overrides)
  end

  defp two_item_domain do
    items = [
      make_item(%{id: 1, quantity: 2, product: make_product(%{id: 10, amount: 500})}),
      make_item(%{id: 2, quantity: 1, product: make_product(%{id: 20, amount: 800})})
    ]

    CartDomain.new(42, items)
  end

  # ── Pipeline execution order ─────────────────────────────────────────

  describe "Interceptor.execute/2 ordering" do
    test "enter phases run left-to-right, leave phases run right-to-left" do
      ctx = %Context{event: :test, data: %{}, domain: nil, ui: nil}
      result = Interceptor.execute([FirstTracker, SecondTracker], ctx)

      assert result.data.log == [:first_enter, :second_enter, :second_leave, :first_leave]
    end

    test "empty pipeline passes context through unchanged" do
      ctx = %Context{event: :test, data: %{x: 1}, domain: nil, ui: nil}
      assert Interceptor.execute([], ctx) == ctx
    end

    test "single interceptor runs both enter and leave" do
      ctx = %Context{event: :test, data: %{}, domain: nil, ui: nil}
      result = Interceptor.execute([FirstTracker], ctx)

      assert result.data.log == [:first_enter, :first_leave]
    end
  end

  # ── DomainDispatch ───────────────────────────────────────────────────

  describe "DomainDispatch" do
    test "dispatches event to CartDomain and collects outcomes" do
      domain = two_item_domain()

      ctx = %Context{
        event: :update_quantity,
        data: %{item_id: 1, delta: 1},
        domain: domain,
        ui: CartUI.new()
      }

      result = DomainDispatch.enter(ctx)

      updated = Enum.find(result.domain.items, &(&1.id == 1))
      assert updated.quantity == 3
      assert length(result.outcomes) > 0
    end

    test "accumulates outcomes from previous interceptors" do
      domain = two_item_domain()
      prior_outcome = {:flash, :info, "prior"}

      ctx = %Context{
        event: :update_quantity,
        data: %{item_id: 1, delta: 1},
        domain: domain,
        ui: CartUI.new(),
        outcomes: [prior_outcome]
      }

      result = DomainDispatch.enter(ctx)

      assert hd(result.outcomes) == prior_outcome
      assert length(result.outcomes) > 1
    end
  end

  # ── UIDispatch ───────────────────────────────────────────────────────

  describe "UIDispatch" do
    test "dispatches switch_tab to CartUI" do
      ctx = %Context{
        event: :switch_tab,
        data: %{tab: :summary},
        domain: two_item_domain(),
        ui: CartUI.new()
      }

      result = UIDispatch.enter(ctx)
      assert result.ui.active_tab == :summary
    end

    test "ignores events CartUI doesn't handle" do
      ctx = %Context{
        event: :update_quantity,
        data: %{item_id: 1, delta: 1},
        domain: two_item_domain(),
        ui: CartUI.new()
      }

      result = UIDispatch.enter(ctx)
      assert result.ui == CartUI.new()
      assert result.outcomes == []
    end
  end

  # ── SignalRouter ─────────────────────────────────────────────────────

  describe "SignalRouter" do
    test "routes signal outcomes to CartUI.react and removes them" do
      ctx = %Context{
        event: :apply_promo,
        data: %{},
        domain: nil,
        ui: %{CartUI.new() | promo_error: "some error"},
        outcomes: [
          {:flash, :info, "Applied!"},
          {:signal, :promo_applied}
        ]
      }

      result = SignalRouter.leave(ctx)

      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
      assert Enum.any?(result.outcomes, &match?({:flash, :info, _}, &1))
      assert result.ui.promo_error == nil
    end

    test "passes through when no signals present" do
      outcomes = [{:flash, :info, "test"}, {:stream_insert, :cart_items, %{}}]

      ctx = %Context{
        event: :test,
        data: %{},
        domain: nil,
        ui: CartUI.new(),
        outcomes: outcomes
      }

      result = SignalRouter.leave(ctx)
      assert result.outcomes == outcomes
    end

    test "handles multiple signals in sequence" do
      ctx = %Context{
        event: :test,
        data: %{},
        domain: nil,
        ui: CartUI.new(),
        outcomes: [
          {:signal, :item_removed},
          {:signal, :checkout_started}
        ]
      }

      result = SignalRouter.leave(ctx)
      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
    end
  end

  # ── Full pipeline integration ────────────────────────────────────────

  describe "full pipeline" do
    test "domain + signal_router pipeline handles update_quantity" do
      domain = two_item_domain()

      ctx = %Context{
        event: :update_quantity,
        data: %{item_id: 1, delta: 1},
        domain: domain,
        ui: CartUI.new()
      }

      result = Interceptor.execute([DomainDispatch, SignalRouter], ctx)

      updated = Enum.find(result.domain.items, &(&1.id == 1))
      assert updated.quantity == 3
      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
    end

    test "domain + signal_router pipeline handles remove_item with undo" do
      domain = two_item_domain()

      ctx = %Context{
        event: :remove_item,
        data: %{item_id: 1},
        domain: domain,
        ui: CartUI.new()
      }

      result = Interceptor.execute([DomainDispatch, SignalRouter], ctx)

      assert result.domain.pending_undo != nil
      assert Enum.any?(result.outcomes, &match?({:start_undo_timer, _}, &1))
      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
    end

    test "full pipeline (domain + ui + signal) handles apply_promo" do
      domain = two_item_domain()

      ctx = %Context{
        event: :apply_promo,
        data: %{code: "SAVE10", valid: true},
        domain: domain,
        ui: %{CartUI.new() | promo_error: "old error"}
      }

      result = Interceptor.execute([DomainDispatch, UIDispatch, SignalRouter], ctx)

      assert result.domain.promo_code == "SAVE10"
      assert result.ui.promo_error == nil
      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
    end

    test "ui-only pipeline handles switch_tab" do
      ctx = %Context{
        event: :switch_tab,
        data: %{tab: :saved},
        domain: two_item_domain(),
        ui: CartUI.new()
      }

      result = Interceptor.execute([UIDispatch], ctx)

      assert result.ui.active_tab == :saved
      assert result.outcomes == []
    end

    test "save_for_later pipeline routes item_saved signal" do
      domain = two_item_domain()

      ctx = %Context{
        event: :save_for_later,
        data: %{item_id: 1},
        domain: domain,
        ui: CartUI.new()
      }

      result = Interceptor.execute([DomainDispatch, SignalRouter], ctx)

      assert length(result.domain.saved_items) == 1
      assert length(result.domain.items) == 1
      refute Enum.any?(result.outcomes, &match?({:signal, _}, &1))
    end

    test "pipeline declarations are inspectable data" do
      pipelines = %{
        update_quantity: [DomainDispatch, SignalRouter],
        switch_tab: [UIDispatch],
        checkout: [Amazin.Interceptors.InjectStock, DomainDispatch, SignalRouter]
      }

      assert length(pipelines.checkout) == 3
      assert hd(pipelines.checkout) == Amazin.Interceptors.InjectStock
      assert pipelines.switch_tab == [UIDispatch]
    end
  end
end
