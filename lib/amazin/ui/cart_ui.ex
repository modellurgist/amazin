defmodule Amazin.UI.CartUI do
  @moduledoc """
  UI state machine for V14 Dual + Signals.

  Owns presentation-only concerns (active tab, validation messages).
  Two entry points:

  - `handle/3` — called by the LiveView for every event (parallel dispatch).
    CartUI handles the events it cares about and ignores the rest.
  - `react/2` — called when CartDomain emits a `{:signal, name}` outcome.
    This is the one-way coupling seam: domain tells UI *what happened*,
    UI decides *how to react* without knowing domain internals.
  """

  import Amazin.Outcome

  defstruct active_tab: :items,
            promo_error: nil

  @type t :: %__MODULE__{
          active_tab: :items | :summary | :saved,
          promo_error: String.t() | nil
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  # ── Direct UI event handlers ───────────────────────────────────────────

  @spec handle(atom(), map(), t()) :: {t(), [term()]}

  def handle(:switch_tab, %{tab: tab}, ui) do
    {%{ui | active_tab: tab}, []}
  end

  def handle(:apply_promo, %{valid: false}, ui) do
    {%{ui | promo_error: "Invalid promo code"}, []}
  end

  def handle(:apply_promo, %{valid: true}, ui) do
    {%{ui | promo_error: nil}, []}
  end

  def handle(_event, _data, ui), do: {ui, []}

  # ── Signal reactors — domain tells UI what happened ────────────────────

  @spec react(atom(), t()) :: {t(), [term()]}

  def react(:checkout_started, ui) do
    {ui, []}
  end

  def react(:item_removed, ui) do
    {ui, []}
  end

  def react(:promo_applied, ui) do
    {%{ui | promo_error: nil}, []}
  end

  def react(:item_saved, ui) do
    {ui, []}
  end

  def react(:item_restored, ui) do
    {ui, []}
  end

  def react(:shipping_changed, ui) do
    {ui, []}
  end

  def react(_signal, ui), do: {ui, []}
end
