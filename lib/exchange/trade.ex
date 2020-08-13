defmodule Exchange.Trade do
  @moduledoc """
  Placeholder to define trades
  """

  alias Exchange.Order

  defstruct trade_id: UUID.uuid1(),
            ticker: nil,
            currency: nil,
            buyer_id: nil,
            seller_id: nil,
            buy_order_id: nil,
            sell_order_id: nil,
            price: nil,
            size: nil,
            buy_init_size: nil,
            sell_init_size: nil,
            type: :full_fill,
            acknowledged_at: :os.system_time(:nanosecond)

  @doc """
  Function that creates a trade given two matching orders

  ## Parameters
   - order: Newly placed order
   - matched_order: Order that is in the `Exchange.OrderBook` that matches the newly placed order
   - type: Atom that can either be `:partial_fill` or `:fulfill`
  """
  @spec generate_trade(
          order :: Exchange.Order.order(),
          matched_order :: Exchange.Order.order(),
          type :: atom,
          currency :: atom
        ) :: %Exchange.Trade{}
  def generate_trade(
        %Order{side: s1, ticker: t1} = order,
        %Order{side: s2} = matched_order,
        type,
        currency
      )
      when s1 != s2 do
    sides = get_sides(order, matched_order)

    %Exchange.Trade{
      trade_id: UUID.uuid1(),
      buy_order_id: sides.buy_order_id,
      buyer_id: sides.buyer_id,
      sell_order_id: sides.sell_order_id,
      seller_id: sides.seller_id,
      buy_init_size: sides.buy_init_size,
      sell_init_size: sides.sell_init_size,
      size: min(order.size, matched_order.size),
      price: matched_order.price,
      type: type,
      acknowledged_at: :os.system_time(:nanosecond),
      ticker: t1,
      currency: currency
    }
  end

  defp get_sides(order, matched_order) do
    if order.side == :buy do
      %{
        buy_order_id: order.order_id,
        buyer_id: order.trader_id,
        sell_order_id: matched_order.order_id,
        seller_id: matched_order.trader_id,
        buy_init_size: order.initial_size,
        sell_init_size: matched_order.initial_size
      }
    else
      %{
        sell_order_id: order.order_id,
        seller_id: order.trader_id,
        buy_order_id: matched_order.order_id,
        buyer_id: matched_order.trader_id,
        buy_init_size: matched_order.initial_size,
        sell_init_size: order.initial_size
      }
    end
  end
end
