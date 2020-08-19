defmodule RabbitBusTest do
  use ExUnit.Case
  alias Exchange.Adapters.RabbitBus

  setup_all _context do
    Supervisor.start_link(
      [
        RabbitBus.Consumer,
        RabbitBus.Producer
      ],
      strategy: :one_for_one,
      name: RabbitBusTest.Supervisor
    )

    :ok
  end

  describe "Validate message passing" do
    setup _context do
      :ok
    end

    test "Order queued" do
      order = Exchange.Utils.sample_order(%{size: 1000, price: 4000, side: :buy})
      order = %Exchange.Order{order | ticker: :AUXLND}
      RabbitBus.add_listener(:order_queued)
      RabbitBus.cast_event(:order_queued, order)

      received_order =
        receive do
          {:cast_event, :order_queued, value} ->
            value
        after
          1_000 -> nil
        end

      assert received_order.order == order
    end

    test "Order cancelled" do
      order = Exchange.Utils.sample_order(%{size: 1000, price: 4000, side: :buy})
      order = %Exchange.Order{order | ticker: :AUXLND}
      RabbitBus.add_listener(:order_cancelled)
      RabbitBus.cast_event(:order_cancelled, order)

      received_order =
        receive do
          {:cast_event, :order_cancelled, value} ->
            value
        after
          1_000 -> nil
        end

      assert received_order.order == order
    end

    test "Order expired" do
      order = Exchange.Utils.sample_order(%{size: 1000, price: 4000, side: :buy})
      order = %Exchange.Order{order | ticker: :AUXLND}
      RabbitBus.add_listener(:order_expired)
      RabbitBus.cast_event(:order_expired, order)

      received_order =
        receive do
          {:cast_event, :order_expired, value} ->
            value
        after
          1_000 -> nil
        end

      assert received_order.order == order
    end

    test "Order placed" do
      alphabet = Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9)
      length = 12

      order_placed = %Exchange.Adapters.MessageBus.OrderPlaced{
        action_indicator: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        client_trans_ref: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        consideration_currency: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        good_until: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        last_modified: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        limit: :rand.uniform(10_000),
        order_id: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        order_time: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        order_value: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        quantity: :rand.uniform(10_000),
        quantity_matched: :rand.uniform(10_000),
        security_id: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        status_code: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        total_commission: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        total_consideration: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        trade_type: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>),
        type_code: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>)
      }

      RabbitBus.add_listener(:order_placed)
      RabbitBus.cast_event(:order_placed, order_placed)

      received_order =
        receive do
          {:cast_event, :order_placed, value} ->
            value
        after
          1_000 -> nil
        end

      assert received_order == order_placed
    end

    test "Price broadcast" do
      price_info = %{
        ticker: :AUXLND,
        ask_min: :rand.uniform(1000),
        bid_max: :rand.uniform(1000)
      }

      RabbitBus.add_listener(:price_broadcast)
      RabbitBus.cast_event(:price_broadcast, price_info)

      received_price =
        receive do
          {:cast_event, :price_broadcast, value} ->
            value
        after
          1_000 -> nil
        end

      assert received_price.ticker == price_info.ticker
      assert received_price.bid_max == price_info.bid_max
      assert received_price.ask_min == price_info.ask_min
    end

    test "Trade executed" do
      order_1 = Exchange.Utils.sample_order(%{size: 1200, price: 3000, side: :buy})
      order_1 = %Exchange.Order{order_1 | ticker: :AUXLND}
      order_2 = Exchange.Utils.sample_order(%{size: 1000, price: 2900, side: :sell})
      order_2 = %Exchange.Order{order_2 | ticker: :AUXLND}
      trade_1 = Exchange.Trade.generate_trade(order_1, order_2, :limit, :EUR)
      RabbitBus.add_listener(:order_queued)
      RabbitBus.add_listener(:trade_executed)
      RabbitBus.cast_event(:order_queued, order_1)
      RabbitBus.cast_event(:order_queued, order_2)
      RabbitBus.cast_event(:trade_executed, trade_1)

      messages =
        1..3
        |> Enum.reduce([], fn _arg, acc ->
          receive do
            {:cast_event, :order_queued, value} ->
              [value.order | acc]

            {:cast_event, :trade_executed, value} ->
              [value.trade | acc]
          after
            1_000 -> acc
          end
        end)

      assert Enum.sort(messages) == Enum.sort([order_1, order_2, trade_1])
    end

    test "Only receive subscribed events" do
      order_1 = Exchange.Utils.sample_order(%{size: 1200, price: 3000, side: :buy})
      order_1 = %Exchange.Order{order_1 | ticker: :AUXLND}
      order_2 = Exchange.Utils.sample_order(%{size: 1000, price: 2900, side: :sell})
      order_2 = %Exchange.Order{order_2 | ticker: :AUXLND}
      trade_1 = Exchange.Trade.generate_trade(order_1, order_2, :limit, :EUR)
      RabbitBus.add_listener(:trade_executed)
      RabbitBus.cast_event(:order_queued, order_1)
      RabbitBus.cast_event(:order_queued, order_2)
      RabbitBus.cast_event(:trade_executed, trade_1)

      messages =
        1..3
        |> Enum.reduce([], fn _arg, acc ->
          receive do
            {:cast_event, :order_queued, value} ->
              [value.order | acc]

            {:cast_event, :trade_executed, value} ->
              [value.trade | acc]
          after
            1_000 -> acc
          end
        end)

      assert Enum.sort(messages) == Enum.sort([trade_1])
    end
  end
end
