defmodule Amazin.Outcome do
  @moduledoc """
  Outcome constructors with signal support for V14 dual-machine coordination.

  Extends the standard outcome vocabulary with `signal/1` and `signal/2` —
  the mechanism by which CartDomain tells CartUI what happened without
  either machine knowing the other's internal structure.
  """

  @spec noop() :: :noop
  def noop, do: :noop

  @spec flash(atom(), String.t()) :: {:flash, atom(), String.t()}
  def flash(level, msg), do: {:flash, level, msg}

  @spec redirect(String.t()) :: {:redirect, String.t()}
  def redirect(url), do: {:redirect, url}

  @spec stream_insert(atom(), term()) :: {:stream_insert, atom(), term()}
  def stream_insert(collection, item), do: {:stream_insert, collection, item}

  @spec stream_delete(atom(), term()) :: {:stream_delete, atom(), term()}
  def stream_delete(collection, item), do: {:stream_delete, collection, item}

  @spec stream_reset(atom(), [term()]) :: {:stream_reset, atom(), [term()]}
  def stream_reset(collection, items), do: {:stream_reset, collection, items}

  @spec push_event(String.t(), map()) :: {:push_event, String.t(), map()}
  def push_event(event, payload), do: {:push_event, event, payload}

  @spec persist_quantity(integer(), integer(), integer()) ::
          {:persist_quantity, integer(), integer(), integer()}
  def persist_quantity(cart_id, item_id, qty), do: {:persist_quantity, cart_id, item_id, qty}

  @spec persist_remove(integer(), integer()) :: {:persist_remove, integer(), integer()}
  def persist_remove(cart_id, item_id), do: {:persist_remove, cart_id, item_id}

  @spec start_checkout([map()], map()) :: {:start_checkout, [map()], map()}
  def start_checkout(line_items, metadata), do: {:start_checkout, line_items, metadata}

  @spec signal(atom()) :: {:signal, atom()}
  def signal(name), do: {:signal, name}

  @spec signal(atom(), term()) :: {:signal, atom(), term()}
  def signal(name, data), do: {:signal, name, data}

  @spec start_undo_timer(integer()) :: {:start_undo_timer, integer()}
  def start_undo_timer(item_id), do: {:start_undo_timer, item_id}

  @spec cancel_undo_timer() :: :cancel_undo_timer
  def cancel_undo_timer, do: :cancel_undo_timer
end
