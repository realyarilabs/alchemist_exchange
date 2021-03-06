defmodule MatchingEngineTest do
  use ExUnit.Case

  alias Exchange.{
    Adapters.InMemoryTimeSeries,
    Adapters.TestEventBus,
    MatchingEngine,
    Order,
    OrderBook,
    Utils
  }

  describe "Spread, bid_max and ask_min queries unit tests:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AUXLND,
        currency: :GBP,
        min_price: 1000,
        max_price: 100_000
      )

      :ok
    end

    test "empty order book" do
      {:ok, spread} = MatchingEngine.spread(:AUXLND)

      {:ok, ask_min} = MatchingEngine.ask_min(:AUXLND)

      {:ok, bid_max} = MatchingEngine.bid_max(:AUXLND)

      assert spread == %Money{amount: 98_998, currency: :GBP}
      assert ask_min == %Money{amount: 99_999, currency: :GBP}
      assert bid_max == %Money{amount: 1001, currency: :GBP}
    end

    test "after one buy order" do
      MatchingEngine.place_order(
        :AUXLND,
        Utils.sample_order(%{size: 1000, price: 4000, side: :buy})
      )

      {:ok, spread} = MatchingEngine.spread(:AUXLND)

      {:ok, ask_min} = MatchingEngine.ask_min(:AUXLND)

      {:ok, bid_max} = MatchingEngine.bid_max(:AUXLND)
      assert spread == %Money{amount: 95_999, currency: :GBP}
      assert ask_min == %Money{amount: 99_999, currency: :GBP}
      assert bid_max == %Money{amount: 4000, currency: :GBP}
    end

    test "spread after one sell order" do
      MatchingEngine.place_order(
        :AUXLND,
        Utils.sample_order(%{size: 500, price: 3900, side: :sell})
      )

      {:ok, spread} = MatchingEngine.spread(:AUXLND)

      {:ok, ask_min} = MatchingEngine.ask_min(:AUXLND)

      {:ok, bid_max} = MatchingEngine.bid_max(:AUXLND)

      assert spread == %Money{amount: 2899, currency: :GBP}
      assert ask_min == %Money{amount: 3900, currency: :GBP}
      assert bid_max == %Money{amount: 1001, currency: :GBP}
    end

    test "spread after several orders" do
      {:ok, spread_1} = MatchingEngine.spread(:AUXLND)
      {:ok, ask_min_1} = MatchingEngine.ask_min(:AUXLND)
      {:ok, bid_max_1} = MatchingEngine.bid_max(:AUXLND)

      MatchingEngine.place_order(
        :AUXLND,
        Utils.sample_order(%{size: 1000, price: 4000, side: :buy})
      )

      {:ok, spread_2} = MatchingEngine.spread(:AUXLND)
      {:ok, ask_min_2} = MatchingEngine.ask_min(:AUXLND)
      {:ok, bid_max_2} = MatchingEngine.bid_max(:AUXLND)

      order = Utils.sample_order(%{size: 500, price: 3900, side: :sell})
      order = %{order | order_id: "10"}

      MatchingEngine.place_order(
        :AUXLND,
        order
      )

      {:ok, spread_3} = MatchingEngine.spread(:AUXLND)
      {:ok, ask_min_3} = MatchingEngine.ask_min(:AUXLND)
      {:ok, bid_max_3} = MatchingEngine.bid_max(:AUXLND)

      order = Utils.sample_order(%{size: 1000, price: 3900, side: :sell})
      order = %{order | order_id: "10"}

      MatchingEngine.place_order(
        :AUXLND,
        order
      )

      {:ok, spread_4} = MatchingEngine.spread(:AUXLND)
      {:ok, ask_min_4} = MatchingEngine.ask_min(:AUXLND)
      {:ok, bid_max_4} = MatchingEngine.bid_max(:AUXLND)

      order = Utils.sample_order(%{size: 250, price: 3800, side: :buy})
      order = %{order | order_id: "11"}

      MatchingEngine.place_order(
        :AUXLND,
        order
      )

      {:ok, spread_5} = MatchingEngine.spread(:AUXLND)
      {:ok, ask_min_5} = MatchingEngine.ask_min(:AUXLND)
      {:ok, bid_max_5} = MatchingEngine.bid_max(:AUXLND)

      assert spread_1 == %Money{amount: 98_998, currency: :GBP}
      assert spread_2 == %Money{amount: 95_999, currency: :GBP}
      assert spread_3 == %Money{amount: 95_999, currency: :GBP}
      assert spread_4 == %Money{amount: 2899, currency: :GBP}
      assert spread_5 == %Money{amount: 100, currency: :GBP}

      assert ask_min_1 == %Money{amount: 99_999, currency: :GBP}
      assert ask_min_2 == %Money{amount: 99_999, currency: :GBP}
      assert ask_min_3 == %Money{amount: 99_999, currency: :GBP}
      assert ask_min_4 == %Money{amount: 3900, currency: :GBP}
      assert ask_min_5 == %Money{amount: 3900, currency: :GBP}

      assert bid_max_1 == %Money{amount: 1001, currency: :GBP}
      assert bid_max_2 == %Money{amount: 4000, currency: :GBP}
      assert bid_max_3 == %Money{amount: 4000, currency: :GBP}
      assert bid_max_4 == %Money{amount: 1001, currency: :GBP}
      assert bid_max_5 == %Money{amount: 3800, currency: :GBP}
    end
  end

  describe "Expirations:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AGZRC,
        currency: :EUR,
        min_price: 1000,
        max_price: 100_000
      )

      Utils.sample_matching_engine_init(:AGZRC)
      :ok
    end

    test "orders with expiration are added to expiration_list" do
      t1 = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      t2 = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 1000

      buy_order =
        Utils.sample_expiring_order(%{size: 1000, price: 3999, side: :buy, id: "9", exp_time: t1})

      sell_order =
        Utils.sample_expiring_order(%{
          size: 1000,
          price: 4020,
          side: :sell,
          id: "10",
          exp_time: t2
        })

      MatchingEngine.place_order(:AGZRC, buy_order)
      MatchingEngine.place_order(:AGZRC, sell_order)
      order_id_1 = buy_order.order_id
      order_id_2 = sell_order.order_id
      {:ok, ob} = MatchingEngine.order_book_entries(:AGZRC)
      assert ob.expiration_list == [{t2, order_id_2}, {t1, order_id_1}]
    end

    test "orders fullfilled are not added to expiration_list" do
      t1 = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      buy_order =
        Utils.sample_expiring_order(%{size: 750, price: 4010, side: :buy, id: "9", exp_time: t1})

      MatchingEngine.place_order(:AGZRC, buy_order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AGZRC)
      assert ob.expiration_list == []
    end

    test "order is automatically cancelled on expiration time" do
      t = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 1

      order =
        Utils.sample_expiring_order(%{size: 1000, price: 3999, side: :buy, id: "9", exp_time: t})

      MatchingEngine.place_order(:AGZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AGZRC)
      assert [{t, order.order_id}] == ob.expiration_list
      assert [] == ob.expired_orders
    end
  end

  describe "Placing and canceling orders:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AUXZRC,
        currency: :EUR,
        min_price: 1000,
        max_price: 100_000
      )

      Utils.sample_matching_engine_init(:AUXZRC)
      :ok
    end

    test "Place a market buy order that consumes the top of the sell side" do
      order = Utils.sample_order(%{size: 2000, price: 0, side: :buy})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      {:ok, spread} = MatchingEngine.spread(:AUXZRC)
      {:ok, ask_min} = MatchingEngine.ask_min(:AUXZRC)
      {:ok, bid_max} = MatchingEngine.bid_max(:AUXZRC)
      assert Enum.count(ob.sell) == 1
      assert spread == %Money{amount: 20, currency: :EUR}
      assert ask_min == %Money{amount: 4020, currency: :EUR}
      assert bid_max == %Money{amount: 4000, currency: :EUR}
    end

    test "Place a market sell order that consumes the top of the buy side" do
      order = Utils.sample_order(%{size: 750, price: 0, side: :sell})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)

      {:ok, spread} = MatchingEngine.spread(:AUXZRC)
      {:ok, ask_min} = MatchingEngine.ask_min(:AUXZRC)
      {:ok, bid_max} = MatchingEngine.bid_max(:AUXZRC)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      assert Enum.count(ob.buy) == 2
      assert spread == %Money{amount: 40, currency: :EUR}
      assert ask_min == %Money{amount: 4010, currency: :EUR}
      assert bid_max == %Money{amount: 3970, currency: :EUR}
    end

    test "Place a market buy order that partially consumes the top order of the sell side" do
      order = Utils.sample_order(%{size: 100, price: 0, side: :buy})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order = ob.sell[4010] |> Enum.find(%Order{}, fn order -> order.order_id == "1" end)
      assert Map.get(partial_order, :size) == 650
    end

    test "Place a market sell order that partially consumes the top order of the buy side" do
      order = Utils.sample_order(%{size: 100, price: 0, side: :sell})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order = ob.buy[4000] |> Enum.find(%Order{}, fn order -> order.order_id == "4" end)
      assert Map.get(partial_order, :size) == 150
    end

    test "Place a market buy order that is partially filled" do
      order = Utils.sample_order(%{size: 10_000, price: 0, side: :buy})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order =
        ob.buy[ob.bid_max] |> Enum.find(%Order{}, fn order -> order.order_id == "9" end)

      assert Map.get(partial_order, :size) == 7750
    end

    test "Place a market sell order that partially filled" do
      order = Utils.sample_order(%{size: 10_000, price: 0, side: :sell})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order =
        ob.sell[ob.ask_min] |> Enum.find(%Order{}, fn order -> order.order_id == "9" end)

      assert Map.get(partial_order, :size) == 8350
    end

    test "Place a limit buy order that consumes the top of the sell side" do
      order = Utils.sample_order(%{size: 2000, price: 4010, side: :buy})

      MatchingEngine.place_order(:AUXZRC, order)

      {:ok, spread} = MatchingEngine.spread(:AUXZRC)
      {:ok, ask_min} = MatchingEngine.ask_min(:AUXZRC)
      {:ok, bid_max} = MatchingEngine.bid_max(:AUXZRC)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      assert Enum.count(ob.sell) == 1
      assert spread == %Money{amount: 20, currency: :EUR}
      assert ask_min == %Money{amount: 4020, currency: :EUR}
      assert bid_max == %Money{amount: 4000, currency: :EUR}
    end

    test "Place a limit sell order that consumes the top of the buy side" do
      order = Utils.sample_order(%{size: 750, price: 4000, side: :sell})

      MatchingEngine.place_order(:AUXZRC, order)

      {:ok, spread} = MatchingEngine.spread(:AUXZRC)
      {:ok, ask_min} = MatchingEngine.ask_min(:AUXZRC)
      {:ok, bid_max} = MatchingEngine.bid_max(:AUXZRC)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      assert Enum.count(ob.buy) == 2
      assert spread == %Money{amount: 40, currency: :EUR}
      assert ask_min == %Money{amount: 4010, currency: :EUR}
      assert bid_max == %Money{amount: 3970, currency: :EUR}
    end

    test "Place a limit buy order that partially consumes the top order of the sell side" do
      order = Utils.sample_order(%{size: 100, price: 4010, side: :buy})
      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = ob.sell[4010] |> Enum.find(%Order{}, fn order -> order.order_id == "1" end)
      assert Map.get(partial_order, :size) == 650
    end

    test "Place a limit sell order that partially consumes the top order of the buy side" do
      order = Utils.sample_order(%{size: 100, price: 4000, side: :sell})

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order = ob.buy[4000] |> Enum.find(%Order{}, fn order -> order.order_id == "4" end)
      assert Map.get(partial_order, :size) == 150
    end

    test "Place a limit buy order that is partially filled" do
      order = Utils.sample_order(%{size: 10_000, price: 4010, side: :buy})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order =
        ob.buy[ob.bid_max] |> Enum.find(%Order{}, fn order -> order.order_id == "9" end)

      assert Map.get(partial_order, :size) == 7750
      assert Map.get(partial_order, :initial_size) == 10_000
      refute ob.sell[4010]
    end

    test "Place a limit sell order that partially filled" do
      order = Utils.sample_order(%{size: 10_000, price: 4000, side: :sell})
      order = %Order{order | type: :market}

      MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order =
        ob.sell[ob.ask_min] |> Enum.find(%Order{}, fn order -> order.order_id == "9" end)

      assert Map.get(partial_order, :size) == 8350
      assert Map.get(partial_order, :initial_size) == 10_000
      refute ob.buy[4000]
    end

    test "Place limit order with price higher than max_price" do
      order = Utils.sample_order(%{size: 100, price: 190_000, side: :sell})

      code = MatchingEngine.place_order(:AUXZRC, order)

      assert code == {:error, :max_price_exceeded}
    end

    test "Place limit order with price lower than min_price" do
      order = Utils.sample_order(%{size: 100, price: 900, side: :sell})

      code = MatchingEngine.place_order(:AUXZRC, order)

      assert code == {:error, :behind_min_price}
    end

    test "Place limit order with existing id" do
      order = Utils.sample_order(%{size: 100, price: 10_000, side: :sell})
      order = %Order{order | order_id: "4"}

      code = MatchingEngine.place_order(:AUXZRC, order)

      assert code == :error
    end

    test "Place market order with existing id" do
      order = Utils.sample_order(%{size: 100, price: 10_000, side: :sell})
      order = %Order{order | type: :market, order_id: "4"}

      code = MatchingEngine.place_order(:AUXZRC, order)

      assert code == :error
    end

    test "Cancel existing order" do
      MatchingEngine.cancel_order(:AUXZRC, "4")
      {code, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      assert code == :ok
      refute OrderBook.fetch_order_by_id(ob, 4)
    end

    test "Cancel inexisting order" do
      code = MatchingEngine.cancel_order(:AUXZRC, "")
      assert code == :error
    end

    test "Place marketable limit order(fullfilled)" do
      order = Utils.sample_order(%{size: 100, price: 0, side: :sell})
      order = %{order | type: :marketable_limit}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = OrderBook.fetch_order_by_id(ob, "4")
      assert partial_order.initial_size == 250
      assert partial_order.size == 150
      assert partial_order.side == :buy
    end

    test "Place marketable limit order(partial)" do
      order = Utils.sample_order(%{size: 2100, price: 0, side: :buy})
      order = %{order | type: :marketable_limit, order_id: "120"}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = OrderBook.fetch_order_by_id(ob, "120")
      assert partial_order.initial_size == 2100
      assert partial_order.size == 100
      assert partial_order.price == 4010
    end

    test "Place buy marketable limit order with empty sell" do
      order = Utils.sample_order(%{size: 2250, price: 4500, side: :buy})
      order = %{order | order_id: "100"}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      order = Utils.sample_order(%{size: 1000, price: 0, side: :buy})
      order = %{order | type: :marketable_limit, order_id: "120"}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = OrderBook.fetch_order_by_id(ob, "120")
      assert partial_order.size == 1000
      assert partial_order.price == ob.max_price - 1
    end

    test "Place stop loss" do
      order = Utils.sample_order(%{size: 2100, price: 4010, side: :buy})
      order = %{order | order_id: "100", type: :stop_loss, stop: 20}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      partial_order = OrderBook.fetch_order_by_id(ob, "100")
      assert partial_order.size == 100
      assert partial_order.order_id == "100"
    end

    test "Place stop loss and trigger it to market" do
      order = Utils.sample_order(%{size: 2100, price: 4010, side: :buy})
      order = %{order | order_id: "100", type: :stop_loss, stop: 20}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      order = Utils.sample_order(%{size: 1000, price: 4010, side: :buy})
      order = %{order | order_id: "101", type: :market}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = OrderBook.fetch_order_by_id(ob, "100")
      assert partial_order.size == 100
      assert partial_order.order_id == "100"
      assert partial_order.price == ob.max_price - 1
    end

    test "Place stop loss order, trigger and complete it trade" do
      order = Utils.sample_order(%{size: 1000, price: 4010, side: :sell})
      order = %{order | order_id: "100", type: :stop_loss, stop: 20}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      order = Utils.sample_order(%{size: 1000, price: 3000, side: :buy})
      order = %{order | order_id: "102", type: :limit}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      order = Utils.sample_order(%{size: 1650, price: 4010, side: :sell})
      order = %{order | order_id: "101", type: :market}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      partial_order = OrderBook.fetch_order_by_id(ob, "100")
      assert partial_order == nil
    end

    test "Place stop loss orders, trigger and complete both to trade" do
      order = Utils.sample_order(%{size: 1000, price: 4008, side: :sell})
      order = %{order | order_id: "100", type: :stop_loss, stop: 1}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      order = Utils.sample_order(%{size: 1000, price: 3819, side: :buy})
      order = %{order | order_id: "101", type: :stop_loss, stop: 5}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      order = Utils.sample_order(%{size: 1500, price: 0, side: :sell})
      order = %{order | order_id: "102", type: :market}
      _code = MatchingEngine.place_order(:AUXZRC, order)

      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)

      order_1 = OrderBook.fetch_order_by_id(ob, "100")
      order_2 = OrderBook.fetch_order_by_id(ob, "101")
      assert order_1 == nil
      assert order_2 == nil
    end

    test "Place stop loss order with order already at the stop" do
      order = Utils.sample_order(%{size: 1650, price: 5000, side: :sell})
      order = %{order | order_id: "100", type: :stop_loss, stop: 1}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      order = Utils.sample_order(%{size: 2250, price: 3000, side: :buy})
      order = %{order | order_id: "101", type: :stop_loss, stop: 1}
      _code = MatchingEngine.place_order(:AUXZRC, order)
      {:ok, ob} = MatchingEngine.order_book_entries(:AUXZRC)
      assert ob.buy == %{}
      assert ob.sell == %{}
    end
  end

  describe "Volume queries:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AGLND,
        currency: :GBP,
        min_price: 1000,
        max_price: 100_000
      )

      Utils.sample_matching_engine_init(:AGLND)
      :ok
    end

    test "sample order book" do
      {:ok, ask_volume} = MatchingEngine.ask_volume(:AGLND)
      {:ok, bid_volume} = MatchingEngine.bid_volume(:AGLND)
      assert ask_volume == 2250
      assert bid_volume == 1650
    end

    test "Volumes after sell order that consumes the buy side" do
      order = Utils.sample_order(%{size: 1800, price: 1010, side: :sell})

      MatchingEngine.place_order(:AGLND, order)

      {:ok, ask_volume} = MatchingEngine.ask_volume(:AGLND)
      {:ok, bid_volume} = MatchingEngine.bid_volume(:AGLND)
      assert ask_volume == 2400
      assert bid_volume == 0
    end

    test "Volumes after sell order that partially consumes the buy side" do
      order = Utils.sample_order(%{size: 1500, price: 1010, side: :sell})

      MatchingEngine.place_order(:AGLND, order)

      {:ok, ask_volume} = MatchingEngine.ask_volume(:AGLND)
      {:ok, bid_volume} = MatchingEngine.bid_volume(:AGLND)
      assert ask_volume == 2250
      assert bid_volume == 150
    end

    test "Volumes after buy order that consumes the sell side" do
      order = Utils.sample_order(%{size: 2500, price: 4050, side: :buy})

      MatchingEngine.place_order(:AGLND, order)

      {:ok, ask_volume} = MatchingEngine.ask_volume(:AGLND)
      {:ok, bid_volume} = MatchingEngine.bid_volume(:AGLND)
      assert ask_volume == 0
      assert bid_volume == 1900
    end

    test "Volumes after buy order that partially consumes the sell side" do
      order = Utils.sample_order(%{size: 2000, price: 4050, side: :buy})

      MatchingEngine.place_order(:AGLND, order)

      {:ok, ask_volume} = MatchingEngine.ask_volume(:AGLND)
      {:ok, bid_volume} = MatchingEngine.bid_volume(:AGLND)
      assert ask_volume == 250
      assert bid_volume == 1650
    end
  end

  describe "Total orders queries:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AUXUS,
        currency: :USD,
        min_price: 1000,
        max_price: 100_000
      )

      Utils.sample_matching_engine_init(:AUXUS)
      :ok
    end

    test "After adding buy order that consumes 1 or more sell orders" do
      order = Utils.sample_order(%{size: 2000, price: 4010, side: :buy})

      MatchingEngine.place_order(:AUXUS, order)
      {:ok, total_bid_orders} = MatchingEngine.total_bid_orders(:AUXUS)
      {:ok, total_ask_orders} = MatchingEngine.total_ask_orders(:AUXUS)
      assert total_bid_orders == 4
      assert total_ask_orders == 1
    end

    test "After adding sell order that consumes 1 or more buy orders" do
      order = Utils.sample_order(%{size: 2000, price: 4000, side: :sell})

      MatchingEngine.place_order(:AUXUS, order)
      {:ok, total_bid_orders} = MatchingEngine.total_bid_orders(:AUXUS)
      {:ok, total_ask_orders} = MatchingEngine.total_ask_orders(:AUXUS)
      assert total_bid_orders == 2
      assert total_ask_orders == 5
    end

    test "After adding buy order" do
      order = Utils.sample_order(%{size: 2000, price: 3000, side: :buy})

      MatchingEngine.place_order(:AUXUS, order)

      {:ok, total_bid_orders} = MatchingEngine.total_bid_orders(:AUXUS)

      {:ok, total_ask_orders} = MatchingEngine.total_ask_orders(:AUXUS)

      assert total_bid_orders == 5
      assert total_ask_orders == 4
    end

    test "After adding sell order" do
      order = Utils.sample_order(%{size: 1000, price: 5000, side: :sell})

      MatchingEngine.place_order(:AUXUS, order)

      {:ok, total_bid_orders} = MatchingEngine.total_bid_orders(:AUXUS)

      {:ok, total_ask_orders} = MatchingEngine.total_ask_orders(:AUXUS)

      assert total_bid_orders == 4
      assert total_ask_orders == 5
    end

    test "Sample order book" do
      {:ok, total_bid_orders} = MatchingEngine.total_bid_orders(:AUXUS)

      {:ok, total_ask_orders} = MatchingEngine.total_ask_orders(:AUXUS)

      assert total_bid_orders == 4
      assert total_ask_orders == 4
    end
  end

  describe "Open orders queries:" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :KAPPA,
        currency: :GBP,
        min_price: 1000,
        max_price: 100_000
      )

      Utils.sample_matching_engine_init(:KAPPA)
      :ok
    end

    test "Sample order book" do
      ids =
        ~w(alchemist1 alchemist2 alchemist3 alchemist4 alchemist5 alchemist6 alchemist7 alchemist8)

      {:ok, orders} = MatchingEngine.open_orders(:KAPPA)

      active = orders |> Enum.map(& &1.trader_id) |> Enum.sort()
      assert ids == active
    end

    test "Get orders from specific trader_id" do
      {:ok, orders} = MatchingEngine.open_orders_by_trader(:KAPPA, "alchemist1")

      active = orders |> Enum.map(&Map.get(&1, :trader_id, nil))
      assert Enum.count(active) == 1
      assert active == ["alchemist1"]
    end

    test "Get orders from non existing trader_id" do
      {:ok, orders} = MatchingEngine.open_orders_by_trader(:KAPPA, "alchemist0")
      active = orders |> Enum.map(& &1.trader_id)
      assert active == []
    end

    test "Sell order that consumes the top buy side" do
      ids = ~w(alchemist0 alchemist3 alchemist4 alchemist5 alchemist6 alchemist7 alchemist8)
      order = Utils.sample_order(%{size: 2000, price: 4000, side: :sell})
      order = %Order{order | trader_id: "alchemist0"}

      MatchingEngine.place_order(:KAPPA, order)

      {:ok, orders} = MatchingEngine.open_orders_by_trader(:KAPPA, "alchemist0")

      {:ok, total_orders} = MatchingEngine.open_orders(:KAPPA)

      active = orders |> Enum.map(& &1.trader_id)
      total_active = total_orders |> Enum.map(& &1.trader_id) |> Enum.sort()
      assert Enum.count(active) == 1
      assert total_active == ids
    end

    test "get open order by id" do
      order_1 = Utils.sample_order(%{size: 2000, price: 3200, side: :buy})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}

      MatchingEngine.place_order(:KAPPA, order_1)

      {:ok, order} = MatchingEngine.open_order_by_id(:KAPPA, "100")

      assert order == order_1
    end

    test "Multiple order placing" do
      ids = ~w(alchemist0 alchemist0 alchemist1 alchemist2 alchemist3 alchemist4
                alchemist5 alchemist6 alchemist7 alchemist8)
      order_1 = Utils.sample_order(%{size: 2000, price: 3200, side: :buy})
      order_2 = Utils.sample_order(%{size: 2100, price: 3000, side: :buy})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}
      order_2 = %Order{order_2 | trader_id: "alchemist0"}

      MatchingEngine.place_order(:KAPPA, order_1)

      MatchingEngine.place_order(:KAPPA, order_2)

      {:ok, orders} = MatchingEngine.open_orders_by_trader(:KAPPA, "alchemist0")

      {:ok, total_orders} = MatchingEngine.open_orders(:KAPPA)

      active = orders |> Enum.map(& &1.trader_id)
      total_active = total_orders |> Enum.map(& &1.trader_id) |> Enum.sort()
      assert Enum.count(active) == 2
      assert total_active == ids
    end

    test "Last price and size" do
      {:ok, last_buy_price} = MatchingEngine.last_price(:KAPPA, :buy)
      {:ok, last_buy_size} = MatchingEngine.last_size(:KAPPA, :buy)
      {:ok, last_sell_price} = MatchingEngine.last_price(:KAPPA, :sell)
      {:ok, last_sell_size} = MatchingEngine.last_size(:KAPPA, :sell)
      assert last_buy_price == 3960
      assert last_buy_size == 150
      assert last_sell_price == 4020
      assert last_sell_size == 250
    end
  end

  describe "Message bus" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :BTCUS,
        currency: :USD,
        min_price: 1000,
        max_price: 100_000
      )

      TestEventBus.flush()

      :ok
    end

    test "Check if trade_executed event is correctly broadcasted" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 1010, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}
      order_2 = %Order{order_2 | trader_id: "alchemist9", order_id: "101"}
      ids = ~w(100 101)
      MatchingEngine.place_order(:BTCUS, order_1)
      MatchingEngine.place_order(:BTCUS, order_2)

      order_queued_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :order_queued
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          payload.order.order_id
        end)

      trade_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :trade_executed
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          {payload.trade.buyer_id, payload.trade.seller_id, payload.trade.buy_order_id,
           payload.trade.sell_order_id}
        end)

      [{buyer_id, seller_id, buy_order_id, sell_order_id} | _tail] = trade_ids
      assert order_queued_ids == ids
      assert Enum.count(order_queued_ids) == 2
      assert buyer_id == "alchemist0"
      assert seller_id == "alchemist9"
      assert sell_order_id == "101"
      assert buy_order_id == "100"
      assert Enum.count(trade_ids) == 1
    end

    test "Check if order_cancelled event is correctly broadcasted" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 2000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}
      order_2 = %Order{order_2 | trader_id: "alchemist9"}
      ids = ~w(100 9)
      MatchingEngine.place_order(:BTCUS, order_1)
      MatchingEngine.place_order(:BTCUS, order_2)
      MatchingEngine.cancel_order(:BTCUS, "9")
      MatchingEngine.cancel_order(:BTCUS, "100")

      order_queued_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :order_queued
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          payload.order.order_id
        end)

      cancel_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :order_cancelled
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          payload.order.order_id
        end)

      assert order_queued_ids == ids
      assert Enum.count(order_queued_ids) == 2
      assert cancel_ids == Enum.reverse(ids)
      assert Enum.count(cancel_ids) == 2
    end

    test "Check if order_expired event is correctly broadcasted" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      t = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 2000
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", exp_time: t}

      MatchingEngine.place_order(:BTCUS, order_1)
      :timer.sleep(3000)

      expired_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :order_expired
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          payload.order.order_id
        end)

      assert expired_ids == ["100"]
      assert Enum.count(expired_ids) == 1
    end

    test "Check if order_queued event is correctly broadcasted" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 2000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}
      order_2 = %Order{order_2 | trader_id: "alchemist0"}
      ids = ~w(100 9)
      MatchingEngine.place_order(:BTCUS, order_1)
      MatchingEngine.place_order(:BTCUS, order_2)

      queue_ids =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :order_queued
        end)
        |> Enum.map(fn {_cast_event, _event, payload} ->
          payload.order.order_id
        end)

      assert queue_ids == ids
      assert Enum.count(queue_ids) == 2
    end

    test "Check if price_broadcast event is correctly broadcasted" do
      :timer.sleep(2000)

      prices =
        TestEventBus.value()
        |> Enum.filter(fn {_cast_event, event, _payload} ->
          event == :price_broadcast
        end)

      assert Enum.uniq(prices)
             |> Enum.map(fn {:cast_event, :price_broadcast, prices} ->
               prices.ticker
             end)
             |> Enum.member?(:BTCUS)

      assert Enum.count(prices) > 0
    end
  end

  describe "Time series" do
    setup _context do
      Exchange.MatchingEngine.start_link(
        ticker: :AGPT,
        currency: :EUR,
        min_price: 1000,
        max_price: 100_000
      )

      InMemoryTimeSeries.flush()

      :ok
    end

    test "check if trade executed event is processed" do
      order_1 = Utils.sample_order(%{size: 1200, price: 3000, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 2900, side: :sell})
      order_3 = Utils.sample_order(%{size: 500, price: 3000, side: :buy})
      order_4 = Utils.sample_order(%{size: 700, price: 3000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", ticker: :AGPT}
      order_2 = %Order{order_2 | trader_id: "alchemist1", order_id: "101", ticker: :AGPT}
      order_3 = %Order{order_3 | trader_id: "alchemist2", order_id: "102", ticker: :AGPT}
      order_4 = %Order{order_4 | trader_id: "alchemist3", order_id: "103", ticker: :AGPT}
      trade_1 = Exchange.Trade.generate_trade(order_1, order_2, :limit, :EUR)
      trade_2 = Exchange.Trade.generate_trade(order_3, order_4, :limit, :EUR)
      trade_1 = %{trade_1 | acknowledged_at: DateTime.utc_now() |> DateTime.to_unix(:nanosecond)}

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_1}
      )

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_2}
      )

      {_code, ts_trade_1} = InMemoryTimeSeries.completed_trades_by_id(:AGPT, "alchemist0")

      {_code, ts_trade_2} = InMemoryTimeSeries.completed_trades_by_id(:AGPT, "alchemist2")

      assert ts_trade_1 == [trade_1]
      assert ts_trade_2 == [trade_2]
    end

    test "get completed trades" do
      order_1 = Utils.sample_order(%{size: 1200, price: 3000, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 2900, side: :sell})
      order_3 = Utils.sample_order(%{size: 500, price: 3000, side: :buy})
      order_4 = Utils.sample_order(%{size: 700, price: 3000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", ticker: :AGPT}
      order_2 = %Order{order_2 | trader_id: "alchemist1", order_id: "101", ticker: :AGPT}
      order_3 = %Order{order_3 | trader_id: "alchemist2", order_id: "102", ticker: :AGPT}
      order_4 = %Order{order_4 | trader_id: "alchemist3", order_id: "103", ticker: :AGPT}
      trade_1 = Exchange.Trade.generate_trade(order_1, order_2, :limit, :EUR)
      trade_2 = Exchange.Trade.generate_trade(order_3, order_4, :limit, :EUR)
      trade_1 = %{trade_1 | acknowledged_at: DateTime.utc_now() |> DateTime.to_unix(:nanosecond)}

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_1}
      )

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_2}
      )

      trades =
        InMemoryTimeSeries.completed_trades(:AGPT)
        |> Enum.sort()

      assert trades == Enum.sort([trade_1, trade_2])
    end

    test "check if orders are queued" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 5000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100"}
      order_2 = %Order{order_2 | trader_id: "alchemist0"}
      ids = ~w(100 9)

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_1}
      )

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_2}
      )

      ts_ids =
        InMemoryTimeSeries.get_state()
        |> elem(1)
        |> Map.get(:orders)
        |> Enum.flat_map(fn {_ts, elem} -> elem end)
        |> Enum.filter(fn order ->
          order.trader_id == "alchemist0"
        end)
        |> Enum.map(fn order ->
          order.order_id
        end)

      assert ts_ids == ids
      assert Enum.count(ts_ids) == 2
    end

    test "check if orders are expired" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 5000, side: :sell})
      t1 = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 2000
      t2 = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 2000
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", exp_time: t1}
      order_2 = %Order{order_2 | trader_id: "alchemist0", exp_time: t2}
      ids = ~w(100 9 100 9)

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_1}
      )

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_2}
      )

      InMemoryTimeSeries.cast_event(
        :order_expired,
        %Exchange.Adapters.MessageBus.OrderExpired{order: order_1}
      )

      InMemoryTimeSeries.cast_event(
        :order_expired,
        %Exchange.Adapters.MessageBus.OrderExpired{order: order_2}
      )

      ts_orders =
        InMemoryTimeSeries.get_state()
        |> elem(1)
        |> Map.get(:orders)
        |> Enum.flat_map(fn {_ts, elem} -> elem end)
        |> Enum.filter(fn order ->
          order.trader_id == "alchemist0"
        end)

      ts_sizes =
        ts_orders
        |> Enum.map(fn order ->
          order.size
        end)

      ts_ids =
        ts_orders
        |> Enum.map(fn order ->
          order.order_id
        end)
        |> Enum.sort()

      assert Enum.count(ts_ids) == 4
      assert ts_ids == Enum.sort(ids)
      assert ts_sizes == [1000, 0, 1000, 0]
    end

    test "check if orders are cancelled" do
      order_1 = Utils.sample_order(%{size: 1000, price: 1010, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 5000, side: :sell})
      t1 = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 2000
      t2 = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - 2000
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", exp_time: t1}
      order_2 = %Order{order_2 | trader_id: "alchemist0", exp_time: t2}
      ids = ~w(100 9 100 9)

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_1}
      )

      InMemoryTimeSeries.cast_event(
        :order_queued,
        %Exchange.Adapters.MessageBus.OrderQueued{order: order_2}
      )

      InMemoryTimeSeries.cast_event(
        :order_cancelled,
        %Exchange.Adapters.MessageBus.OrderCancelled{order: order_1}
      )

      InMemoryTimeSeries.cast_event(
        :order_cancelled,
        %Exchange.Adapters.MessageBus.OrderCancelled{order: order_2}
      )

      ts_orders =
        InMemoryTimeSeries.get_state()
        |> elem(1)
        |> Map.get(:orders)
        |> Enum.flat_map(fn {_ts, elem} -> elem end)
        |> Enum.filter(fn order ->
          order.trader_id == "alchemist0"
        end)

      ts_sizes =
        ts_orders
        |> Enum.map(fn order ->
          order.size
        end)

      ts_ids =
        ts_orders
        |> Enum.map(fn order ->
          order.order_id
        end)
        |> Enum.sort()

      assert Enum.count(ts_ids) == 4
      assert ts_ids == Enum.sort(ids)
      assert ts_sizes == [1000, 0, 1000, 0]
    end

    test "check if prices are broadcasted" do
      price_broadcast_event_1 = %Exchange.Adapters.MessageBus.PriceBroadcast{
        ticker: :AGPT,
        ask_min: 1001,
        bid_max: 99_999
      }

      price_broadcast_event_2 = %Exchange.Adapters.MessageBus.PriceBroadcast{
        ticker: :BTCUS,
        ask_min: 5000,
        bid_max: 70_012
      }

      price_broadcast_event_3 = %Exchange.Adapters.MessageBus.PriceBroadcast{
        ticker: :AUXLND,
        ask_min: 2000,
        bid_max: 80_000
      }

      InMemoryTimeSeries.cast_event(:price_broadcast, price_broadcast_event_1)
      InMemoryTimeSeries.cast_event(:price_broadcast, price_broadcast_event_2)
      InMemoryTimeSeries.cast_event(:price_broadcast, price_broadcast_event_3)

      prices =
        InMemoryTimeSeries.get_state()
        |> elem(1)
        |> Map.get(:prices)
        |> Enum.flat_map(fn {_ts, elem} -> elem end)
        |> Enum.sort()

      assert prices ==
               [
                 price_broadcast_event_1,
                 price_broadcast_event_2,
                 price_broadcast_event_3
               ]
               |> Enum.map(fn %Exchange.Adapters.MessageBus.PriceBroadcast{
                                ask_min: ask_min,
                                bid_max: bid_max,
                                ticker: ticker
                              } ->
                 %{ask_min: ask_min, bid_max: bid_max, ticker: ticker}
               end)
               |> Enum.sort()
    end

    test "get completed trade by id" do
      order_1 = Utils.sample_order(%{size: 1200, price: 3000, side: :buy})
      order_2 = Utils.sample_order(%{size: 1000, price: 2900, side: :sell})
      order_3 = Utils.sample_order(%{size: 500, price: 3000, side: :buy})
      order_4 = Utils.sample_order(%{size: 700, price: 3000, side: :sell})
      order_1 = %Order{order_1 | trader_id: "alchemist0", order_id: "100", ticker: :AGPT}
      order_2 = %Order{order_2 | trader_id: "alchemist1", order_id: "101", ticker: :AGPT}
      order_3 = %Order{order_3 | trader_id: "alchemist2", order_id: "102", ticker: :AGPT}
      order_4 = %Order{order_4 | trader_id: "alchemist3", order_id: "103", ticker: :AGPT}
      trade_1 = Exchange.Trade.generate_trade(order_1, order_2, :limit, :EUR)
      trade_2 = Exchange.Trade.generate_trade(order_3, order_4, :limit, :EUR)
      trade_1 = %{trade_1 | acknowledged_at: DateTime.utc_now() |> DateTime.to_unix(:nanosecond)}

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_1}
      )

      InMemoryTimeSeries.cast_event(
        :trade_executed,
        %Exchange.Adapters.MessageBus.TradeExecuted{trade: trade_2}
      )

      get_trade_1 = InMemoryTimeSeries.get_completed_trade_by_trade_id(:AGPT, trade_1.trade_id)
      get_trade_2 = InMemoryTimeSeries.get_completed_trade_by_trade_id(:AGPT, trade_2.trade_id)

      assert get_trade_1 == trade_1
      assert get_trade_2 == trade_2
    end
  end
end
