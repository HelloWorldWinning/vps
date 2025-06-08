import sqlite3
from datetime import datetime

import numpy as np
import pandas as pd


def get_complete_trade_data(db_path):
    """
    Get complete trade data with ALL related information from the FreqTrade database
    Each row represents one trade with all associated data
    """
    try:
        conn = sqlite3.connect(db_path)

        # Complex query to get ALL trade-related data
        query = """
        SELECT
            -- Core trade information
            t.id as trade_id,
            t.exchange,
            t.pair,
            t.base_currency,
            t.stake_currency,
            t.is_open,
            t.open_date,
            t.close_date,
            t.strategy,
            t.enter_tag,
            t.exit_reason,
            t.exit_order_status,
            t.timeframe,
            t.trading_mode,

            -- Financial data
            t.stake_amount,
            t.max_stake_amount,
            t.amount,
            t.amount_requested,
            t.open_rate,
            t.open_rate_requested,
            t.close_rate,
            t.close_rate_requested,
            t.realized_profit,
            t.close_profit,
            t.close_profit_abs,

            -- Fees
            t.fee_open,
            t.fee_open_cost,
            t.fee_open_currency,
            t.fee_close,
            t.fee_close_cost,
            t.fee_close_currency,

            -- Stop loss and risk management
            t.stop_loss,
            t.stop_loss_pct,
            t.initial_stop_loss,
            t.initial_stop_loss_pct,
            t.is_stop_loss_trailing,
            t.max_rate,
            t.min_rate,

            -- Trading specifics
            t.open_trade_value,
            t.leverage,
            t.is_short,
            t.liquidation_price,
            t.interest_rate,
            t.funding_fees,
            t.funding_fee_running,
            t.contract_size,

            -- Precision settings
            t.amount_precision,
            t.price_precision,
            t.precision_mode,
            t.precision_mode_price,
            t.record_version,

            -- Buy order information
            buy_order.order_id as buy_order_id,
            buy_order.status as buy_order_status,
            buy_order.order_type as buy_order_type,
            buy_order.price as buy_order_price,
            buy_order.average as buy_order_average,
            buy_order.amount as buy_order_amount,
            buy_order.filled as buy_order_filled,
            buy_order.remaining as buy_order_remaining,
            buy_order.cost as buy_order_cost,
            buy_order.order_date as buy_order_date,
            buy_order.order_filled_date as buy_order_filled_date,
            buy_order.order_update_date as buy_order_update_date,
            buy_order.funding_fee as buy_order_funding_fee,
            buy_order.ft_fee_base as buy_order_ft_fee_base,
            buy_order.ft_order_tag as buy_order_tag,

            -- Sell order information
            sell_order.order_id as sell_order_id,
            sell_order.status as sell_order_status,
            sell_order.order_type as sell_order_type,
            sell_order.price as sell_order_price,
            sell_order.average as sell_order_average,
            sell_order.amount as sell_order_amount,
            sell_order.filled as sell_order_filled,
            sell_order.remaining as sell_order_remaining,
            sell_order.cost as sell_order_cost,
            sell_order.order_date as sell_order_date,
            sell_order.order_filled_date as sell_order_filled_date,
            sell_order.order_update_date as sell_order_update_date,
            sell_order.funding_fee as sell_order_funding_fee,
            sell_order.ft_fee_base as sell_order_ft_fee_base,
            sell_order.ft_order_tag as sell_order_tag,

            -- Order counts
            order_counts.total_orders,
            order_counts.buy_orders,
            order_counts.sell_orders

        FROM trades t

        -- Left join with buy orders (entry orders)
        LEFT JOIN orders buy_order ON (
            t.id = buy_order.ft_trade_id
            AND buy_order.ft_order_side = 'buy'
        )

        -- Left join with sell orders (exit orders)
        LEFT JOIN orders sell_order ON (
            t.id = sell_order.ft_trade_id
            AND sell_order.ft_order_side = 'sell'
        )

        -- Subquery to get order counts per trade
        LEFT JOIN (
            SELECT
                ft_trade_id,
                COUNT(*) as total_orders,
                SUM(CASE WHEN ft_order_side = 'buy' THEN 1 ELSE 0 END) as buy_orders,
                SUM(CASE WHEN ft_order_side = 'sell' THEN 1 ELSE 0 END) as sell_orders
            FROM orders
            GROUP BY ft_trade_id
        ) order_counts ON t.id = order_counts.ft_trade_id

        ORDER BY t.id
        """

        print("Executing comprehensive trade data query...")
        df = pd.read_sql_query(query, conn)

        # Convert date columns to datetime
        date_columns = [
            "open_date",
            "close_date",
            "buy_order_date",
            "buy_order_filled_date",
            "buy_order_update_date",
            "sell_order_date",
            "sell_order_filled_date",
            "sell_order_update_date",
        ]

        for col in date_columns:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors="coerce")

        # Calculate duration in minutes for closed trades
        df["duration_minutes"] = np.nan
        closed_mask = df["close_date"].notna()
        df.loc[closed_mask, "duration_minutes"] = (
            df.loc[closed_mask, "close_date"] - df.loc[closed_mask, "open_date"]
        ).dt.total_seconds() / 60

        # Add additional duration columns
        df["duration_hours"] = df["duration_minutes"] / 60
        df["duration_days"] = df["duration_hours"] / 24

        # Round durations
        df["duration_minutes"] = df["duration_minutes"].round(2)
        df["duration_hours"] = df["duration_hours"].round(2)
        df["duration_days"] = df["duration_days"].round(3)

        # Calculate profit percentage
        df["profit_pct"] = (
            (df["close_rate"] - df["open_rate"]) / df["open_rate"] * 100
        ).round(2)

        # Calculate total fees
        df["total_fees"] = (
            df["fee_open_cost"].fillna(0) + df["fee_close_cost"].fillna(0)
        ).round(4)

        conn.close()

        print(f"Successfully loaded {len(df)} trades with complete data")
        return df

    except Exception as e:
        print(f"Error reading complete trade data: {str(e)}")
        return None


def get_trade_custom_data(db_path):
    """
    Get any custom data associated with trades
    """
    try:
        conn = sqlite3.connect(db_path)

        query = """
        SELECT
            ft_trade_id,
            cd_key,
            cd_type,
            cd_value,
            created_at,
            updated_at
        FROM trade_custom_data
        ORDER BY ft_trade_id, cd_key
        """

        custom_df = pd.read_sql_query(query, conn)
        conn.close()

        if len(custom_df) > 0:
            print(f"Found {len(custom_df)} custom data entries")
            return custom_df
        else:
            print("No custom trade data found")
            return None

    except Exception as e:
        print(f"Error reading custom trade data: {str(e)}")
        return None


def analyze_complete_trade_data(df):
    """
    Comprehensive analysis of the complete trade dataset
    """
    if df is None or len(df) == 0:
        print("No data to analyze")
        return

    print(f"\n{'='*60}")
    print(f"COMPLETE FREQTRADE DATA ANALYSIS")
    print(f"{'='*60}")

    print(f"\n=== BASIC STATISTICS ===")
    print(f"Total trades: {len(df)}")
    print(f"Closed trades: {df['close_date'].notna().sum()}")
    print(f"Open trades: {df['is_open'].sum()}")
    print(f"Unique pairs: {df['pair'].nunique()}")
    print(f"Exchanges: {df['exchange'].unique()}")
    print(f"Strategies: {df['strategy'].unique()}")

    # Closed trades analysis
    closed_trades = df[df["close_date"].notna()].copy()
    if len(closed_trades) > 0:
        print(f"\n=== CLOSED TRADES PERFORMANCE ===")
        print(f"Profitable trades: {(closed_trades['close_profit'] > 0).sum()}")
        print(f"Loss trades: {(closed_trades['close_profit'] < 0).sum()}")
        print(f"Win rate: {(closed_trades['close_profit'] > 0).mean()*100:.1f}%")
        print(f"Average profit: {closed_trades['close_profit'].mean():.4f}")
        print(f"Total profit: {closed_trades['close_profit'].sum():.4f}")
        print(f"Average profit %: {closed_trades['profit_pct'].mean():.2f}%")

        print(f"\n=== DURATION ANALYSIS ===")
        print(f"Average duration: {closed_trades['duration_hours'].mean():.2f} hours")
        print(f"Median duration: {closed_trades['duration_hours'].median():.2f} hours")
        print(f"Min duration: {closed_trades['duration_hours'].min():.2f} hours")
        print(f"Max duration: {closed_trades['duration_hours'].max():.2f} hours")

        print(f"\n=== PAIR PERFORMANCE ===")
        pair_stats = (
            closed_trades.groupby("pair")
            .agg({"close_profit": ["count", "sum", "mean"], "duration_hours": "mean"})
            .round(4)
        )
        pair_stats.columns = [
            "trades",
            "total_profit",
            "avg_profit",
            "avg_duration_hrs",
        ]
        print(pair_stats.sort_values("total_profit", ascending=False))

    print(f"\n=== FEES ANALYSIS ===")
    print(f"Average total fees per trade: {df['total_fees'].mean():.4f}")
    print(f"Total fees paid: {df['total_fees'].sum():.4f}")

    print(f"\n=== ORDERS ANALYSIS ===")
    print(f"Average orders per trade: {df['total_orders'].mean():.1f}")
    print(f"Trades with multiple buy orders: {(df['buy_orders'] > 1).sum()}")
    print(f"Trades with multiple sell orders: {(df['sell_orders'] > 1).sum()}")


def main(db_path):
    # Database path

    print("Loading complete FreqTrade data...")
    print("This includes trades, orders, and all related information")

    # Get complete trade data
    trades_df = get_complete_trade_data(db_path)

    if trades_df is not None:
        print(f"\n=== DATAFRAME INFO ===")
        print(f"Shape: {trades_df.shape}")
        print(f"Columns: {len(trades_df.columns)}")
        print(
            f"Memory usage: {trades_df.memory_usage(deep=True).sum() / 1024**2:.2f} MB"
        )

        print(f"\n=== COLUMN LIST ===")
        for i, col in enumerate(trades_df.columns, 1):
            print(f"{i:2d}. {col}")

        # Show sample of key columns
        print(f"\n=== SAMPLE DATA (Key Columns) ===")
        key_cols = [
            "trade_id",
            "pair",
            "open_date",
            "close_date",
            "duration_minutes",
            "stake_amount",
            "open_rate",
            "close_rate",
            "close_profit",
            "profit_pct",
            "exit_reason",
            "total_orders",
        ]
        print(trades_df[key_cols].head(10))

        # Comprehensive analysis
        analyze_complete_trade_data(trades_df)

        # Get custom data if available
        custom_data = get_trade_custom_data(db_path)

        # Export to CSV
        output_file = "complete_freqtrade_data.csv"
        trades_df.to_csv(output_file, index=False)
        print(f"\n=== EXPORT ===")
        print(f"Complete data exported to: {output_file}")
        print(f"You now have ALL trade-related data in a single DataFrame!")

        return trades_df

    else:
        print("Failed to load trade data")
        return None


if __name__ == "__main__":
    db_path = "/data/bayes_trading_22001/user_data/tradesv3.sqlite"
    df = main(db_path)
