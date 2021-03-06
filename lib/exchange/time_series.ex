defmodule Exchange.TimeSeries do
  @moduledoc """
  Behaviour that a time series database must implement
  to be able to communicate with the Exchange.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @required_config opts[:required_config] || []
      @required_deps opts[:required_deps] || []
      @behaviour Exchange.TimeSeries
      alias Exchange.Adapters.Helpers

      def validate_config(config \\ []) do
        keys = Helpers.validate_config(@required_config, config, __MODULE__)
      end

      @on_load :validate_dependency
      def validate_dependency do
        keys = Helpers.validate_dependency(@required_deps, __MODULE__)
      end
    end
  end

  @doc """
  Callback to initialize the given timeseries adapter
  and return necessary children.
  """
  @callback init :: {:ok, list()}

  @doc """
  Function that fetches the completed trades from a market which a specific user participated.
  """
  @callback completed_trades(atom) :: [Exchange.Trade]

  @doc """
  Function that fetches the completed trades from a market which a specific user participated.
  """
  @callback completed_trades_by_id(atom, String.t()) :: [Exchange.Trade]
  @doc """
  Function that fetches the active orders of the application.
  It is called when the application starts running allowing the recovery of the previous state when a crash happens.
  """
  @callback get_live_orders(atom) :: [Exchange.Order]

  @doc """
  Function that fetches a completed trade from a exchange that matches a trade id
  """
  @callback get_completed_trade_by_trade_id(atom, String.t()) :: Exchange.Trade
end
