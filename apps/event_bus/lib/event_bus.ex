defmodule EventBus do
  @moduledoc """
  Public API to use the Event Bus.
  """

  @behaviour Exchange.MessageBus

  @events ~w(trade_executed order_queued order_cancelled order_expired
             transaction_open order_placed trade_processed)a

  def add_listener(key) do
    if Enum.member?(@events, key) do
      {:ok, _} = Registry.register(EventBus.Registry, key, [])
      :ok
    else
      :error
    end
  end

  def remove_listener(key) do
    if Enum.member?(@events, key) do
      Registry.unregister(EventBus.Registry, key)
    else
      :error
    end
  end

  def cast_event(:order_cancelled, payload),
    do: dispatch_event(:order_cancelled, %EventBus.OrderCancelled{order: payload})

  def cast_event(:trade_executed, payload),
    do: dispatch_event(:trade_executed, %EventBus.TradeExecuted{trade: payload})

  def cast_event(:order_expired, payload),
    do: dispatch_event(:order_expired, %EventBus.OrderExpired{order: payload})

  def cast_event(:order_placed, payload),
    do: dispatch_event(:order_placed, %EventBus.OrderPlaced{} = payload)

  def cast_event(:order_queued, payload),
    do: dispatch_event(:order_queued, %EventBus.OrderQueued{order: payload})

  def cast_event(:trade_processed, payload),
    do: dispatch_event(:trade_processed, %EventBus.TradeProcessed{} = payload)

  defp dispatch_event(key, payload) do
    if Application.get_env(:event_bus, :environment) != :test do
      Registry.dispatch(EventBus.Registry, key, fn entries ->
        for {pid, _} <- entries, do: send(pid, {:cast_event, key, payload})
      end)
    end
  end
end
