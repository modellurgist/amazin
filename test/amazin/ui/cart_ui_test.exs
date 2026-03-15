defmodule Amazin.UI.CartUITest do
  @moduledoc """
  Pure unit tests for CartUI — no Phoenix, no Ecto, no Mox.

  CartUI is the UI state machine in V14's dual-machine architecture.
  Tests cover both `handle/3` (direct UI events) and `react/2` (signal reactors).
  """
  use ExUnit.Case, async: true

  alias Amazin.UI.CartUI

  # ── new/0 ──────────────────────────────────────────────────────────────

  describe "new/0" do
    test "initializes with default UI state" do
      ui = CartUI.new()

      assert ui.active_tab == :items
      assert ui.promo_error == nil
    end
  end

  # ── handle(:switch_tab, ...) ───────────────────────────────────────────

  describe "handle(:switch_tab, ...)" do
    test "changes active tab to summary" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.handle(:switch_tab, %{tab: :summary}, ui)

      assert new_ui.active_tab == :summary
      assert outcomes == []
    end

    test "changes active tab back to items" do
      ui = %{CartUI.new() | active_tab: :summary}

      {new_ui, outcomes} = CartUI.handle(:switch_tab, %{tab: :items}, ui)

      assert new_ui.active_tab == :items
      assert outcomes == []
    end

    test "changes active tab to saved" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.handle(:switch_tab, %{tab: :saved}, ui)

      assert new_ui.active_tab == :saved
      assert outcomes == []
    end
  end

  # ── handle(:apply_promo, ...) ──────────────────────────────────────────

  describe "handle(:apply_promo, ...)" do
    test "invalid promo sets promo_error" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.handle(:apply_promo, %{valid: false}, ui)

      assert new_ui.promo_error == "Invalid promo code"
      assert outcomes == []
    end

    test "valid promo clears promo_error" do
      ui = %{CartUI.new() | promo_error: "Invalid promo code"}

      {new_ui, outcomes} = CartUI.handle(:apply_promo, %{valid: true}, ui)

      assert new_ui.promo_error == nil
      assert outcomes == []
    end
  end

  # ── handle (catch-all) ────────────────────────────────────────────────

  describe "handle (catch-all)" do
    test "ignores events CartUI doesn't handle" do
      ui = CartUI.new()

      {unchanged, outcomes} = CartUI.handle(:update_quantity, %{item_id: 1, delta: 1}, ui)

      assert unchanged == ui
      assert outcomes == []
    end

    test "ignores checkout events" do
      ui = CartUI.new()

      {unchanged, outcomes} = CartUI.handle(:checkout, %{stock_levels: %{}}, ui)

      assert unchanged == ui
      assert outcomes == []
    end
  end

  # ── react(:checkout_started, ...) ──────────────────────────────────────

  describe "react(:checkout_started, ...)" do
    test "returns ui unchanged with no outcomes" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:checkout_started, ui)

      assert new_ui == ui
      assert outcomes == []
    end
  end

  # ── react(:item_removed, ...) ──────────────────────────────────────────

  describe "react(:item_removed, ...)" do
    test "returns ui unchanged with no outcomes" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:item_removed, ui)

      assert new_ui == ui
      assert outcomes == []
    end
  end

  # ── react(:promo_applied, ...) ─────────────────────────────────────────

  describe "react(:promo_applied, ...)" do
    test "clears promo_error" do
      ui = %{CartUI.new() | promo_error: "Invalid promo code"}

      {new_ui, outcomes} = CartUI.react(:promo_applied, ui)

      assert new_ui.promo_error == nil
      assert outcomes == []
    end

    test "is a no-op when promo_error is already nil" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:promo_applied, ui)

      assert new_ui.promo_error == nil
      assert outcomes == []
    end
  end

  # ── react(:item_saved, ...) ────────────────────────────────────────────

  describe "react(:item_saved, ...)" do
    test "returns ui unchanged with no outcomes" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:item_saved, ui)

      assert new_ui == ui
      assert outcomes == []
    end
  end

  # ── react(:item_restored, ...) ─────────────────────────────────────────

  describe "react(:item_restored, ...)" do
    test "returns ui unchanged with no outcomes" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:item_restored, ui)

      assert new_ui == ui
      assert outcomes == []
    end
  end

  # ── react(:shipping_changed, ...) ──────────────────────────────────────

  describe "react(:shipping_changed, ...)" do
    test "returns ui unchanged with no outcomes" do
      ui = CartUI.new()

      {new_ui, outcomes} = CartUI.react(:shipping_changed, ui)

      assert new_ui == ui
      assert outcomes == []
    end
  end

  # ── react (catch-all) ─────────────────────────────────────────────────

  describe "react (catch-all)" do
    test "ignores unknown signals" do
      ui = CartUI.new()

      {unchanged, outcomes} = CartUI.react(:unknown_signal, ui)

      assert unchanged == ui
      assert outcomes == []
    end
  end
end
