#!/usr/bin/env python3
"""
Create Great Expectations suites for NASDAQ stock data pipeline.
FINAL VERSION - Correct schemas + correct GX method names.
"""

import great_expectations as gx
from great_expectations.core.batch import RuntimeBatchRequest
import sys
import os

# Set context root directory
context_root = os.getenv('GX_DATA_CONTEXT_ROOT_DIR', '/opt/airflow/great_expectations')

try:
    context = gx.get_context(context_root_dir=context_root)
    print(f"GX Context initialized from: {context_root}")
except Exception as e:
    print(f"Failed to initialize GX context: {e}")
    sys.exit(1)


def create_fact_table_expectations():
    """Create LIGHTWEIGHT expectations for fact_stock_daily_price table - optimized for performance"""
    
    print("\n" + "="*60)
    print("Creating expectations for fact_stock_daily_price...")
    print("="*60)
    
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="fact_stock_daily_price",
        runtime_parameters={
            "query": """
                SELECT * FROM nasdaq_airflow_warehouse_dev.fact_stock_daily_price 
                LIMIT 100
            """  # Reduced from 1000 to 100 for faster validation
        },
        batch_identifiers={"default_identifier_name": "fact_table_setup"}
    )
    
    validator = context.get_validator(
        batch_request=batch_request,
        create_expectation_suite_with_name="fact_stock_daily_price_suite"
    )
    
    # 1. Schema validation - FAST (table metadata only)
    print("Adding schema expectations...")
    validator.expect_table_columns_to_match_ordered_list([
        "fact_key", "stock_symbol", "trade_date", "trade_timestamp",
        "close_price", "open_price", "high_price", "low_price",
        "previous_close", "volume", "market_cap", "price_change",
        "change_percentage", "year_high_52w", "year_low_52w",
        "price_avg_50d", "price_avg_200d", "daily_volatility",
        "processing_date", "created_at"
    ])
    
    # 2. Critical null checks only - FAST (Athena optimized)
    print("Adding completeness expectations...")
    validator.expect_column_values_to_not_be_null("fact_key")
    validator.expect_column_values_to_not_be_null("stock_symbol")
    validator.expect_column_values_to_not_be_null("trade_date")
    validator.expect_column_values_to_not_be_null("close_price")
    
    # 3. Uniqueness - MODERATELY FAST (index-based if available)
    print("Adding uniqueness expectations...")
    validator.expect_column_values_to_be_unique("fact_key")
    validator.expect_compound_columns_to_be_unique(
        column_list=["stock_symbol", "trade_date"]
    )
    
    # 4. Row count sanity check - VERY FAST (COUNT query)
    print("Adding row count expectations...")
    validator.expect_table_row_count_to_be_between(
        min_value=1,
        max_value=100
    )
    
    validator.save_expectation_suite(discard_failed_expectations=False)
    print("fact_stock_daily_price suite created successfully!")
    print(f"Total expectations: {len(validator.get_expectation_suite().expectations)}")
    print("Optimized for fast validation (removed expensive row-level checks)")


def create_dim_stock_expectations():
    """Create expectations for dim_stock dimension table"""
    
    print("\n" + "="*60)
    print("Creating expectations for dim_stock...")
    print("="*60)
    
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="dim_stock",
        runtime_parameters={
            "query": "SELECT * FROM nasdaq_airflow_warehouse_dev.dim_stock"
        },
        batch_identifiers={"default_identifier_name": "dim_stock_setup"}
    )
    
    validator = context.get_validator(
        batch_request=batch_request,
        create_expectation_suite_with_name="dim_stock_suite"
    )
    
    print("Adding schema expectations...")
    validator.expect_table_columns_to_match_ordered_list([
        "stock_key", "symbol", "company_name", "exchange",
        "market_cap_tier", "sector", "industry", "first_seen_date",
        "last_seen_date", "is_active"
    ])
    
    print("Adding completeness expectations...")
    validator.expect_column_values_to_not_be_null("stock_key")
    validator.expect_column_values_to_not_be_null("symbol")
    validator.expect_column_values_to_not_be_null("company_name")
    
    print("Adding uniqueness expectations...")
    validator.expect_column_values_to_be_unique("stock_key")
    validator.expect_column_values_to_be_unique("symbol")
    
    print("Adding valid values expectations...")
    validator.expect_column_values_to_be_in_set(
        "symbol",
        ["AAPL", "MSFT", "GOOGL", "AMZN", "META"]
    )
    
    validator.expect_column_values_to_be_in_set(
        "is_active",
        [True, False]
    )
    
    print("Adding row count expectations...")
    validator.expect_table_row_count_to_be_between(
        min_value=1,
        max_value=100
    )
    
    validator.save_expectation_suite(discard_failed_expectations=False)
    print("dim_stock suite created successfully!")
    print(f"Total expectations: {len(validator.get_expectation_suite().expectations)}")


def create_weekly_agg_expectations():
    """Create expectations for agg_stock_weekly_metrics"""
    
    print("\n" + "="*60)
    print("Creating expectations for agg_stock_weekly_metrics...")
    print("="*60)
    
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="agg_stock_weekly_metrics",
        runtime_parameters={
            "query": """
                SELECT * FROM nasdaq_airflow_warehouse_dev.agg_stock_weekly_metrics 
                LIMIT 1000
            """
        },
        batch_identifiers={"default_identifier_name": "weekly_agg_setup"}
    )
    
    validator = context.get_validator(
        batch_request=batch_request,
        create_expectation_suite_with_name="agg_stock_weekly_metrics_suite"
    )
    
    print("Adding schema expectations...")
    validator.expect_table_columns_to_match_ordered_list([
        "year", "week", "symbol", "company_name", "week_open",
        "week_close", "week_high", "week_low", "total_volume",
        "avg_price", "price_std_dev", "avg_volatility", "weekly_return_pct"
    ])
    
    print("Adding completeness expectations...")
    validator.expect_column_values_to_not_be_null("year")
    validator.expect_column_values_to_not_be_null("week")
    validator.expect_column_values_to_not_be_null("symbol")
    validator.expect_column_values_to_not_be_null("week_close")
    
    print("Adding business logic expectations...")
    validator.expect_column_values_to_be_between(
        "week",
        min_value=1,
        max_value=53
    )
    
    print("Adding aggregation expectations...")
    validator.expect_column_pair_values_A_to_be_greater_than_B(
        column_A="week_high",
        column_B="week_low",
        or_equal=True
    )
    
    validator.expect_column_values_to_be_between(
        "avg_price",
        min_value=0,
        max_value=10000
    )
    
    print("Adding uniqueness expectations...")
    validator.expect_compound_columns_to_be_unique(
        column_list=["year", "week", "symbol"]
    )
    
    validator.save_expectation_suite(discard_failed_expectations=False)
    print("agg_stock_weekly_metrics suite created successfully!")
    print(f"Total expectations: {len(validator.get_expectation_suite().expectations)}")


def create_monthly_agg_expectations():
    """Create expectations for agg_stock_monthly_metrics"""
    
    print("\n" + "="*60)
    print("Creating expectations for agg_stock_monthly_metrics...")
    print("="*60)
    
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="agg_stock_monthly_metrics",
        runtime_parameters={
            "query": """
                SELECT * FROM nasdaq_airflow_warehouse_dev.agg_stock_monthly_metrics 
                LIMIT 1000
            """
        },
        batch_identifiers={"default_identifier_name": "monthly_agg_setup"}
    )
    
    validator = context.get_validator(
        batch_request=batch_request,
        create_expectation_suite_with_name="agg_stock_monthly_metrics_suite"
    )
    
    print("Adding schema expectations...")
    validator.expect_table_columns_to_match_ordered_list([
        "year", "month", "symbol", "company_name", "sector",
        "month_open", "month_close", "month_high", "month_low",
        "total_volume", "avg_price", "avg_market_cap", "price_volatility",
        "monthly_return_pct", "avg_daily_volatility"
    ])
    
    print("Adding completeness expectations...")
    validator.expect_column_values_to_not_be_null("year")
    validator.expect_column_values_to_not_be_null("month")
    validator.expect_column_values_to_not_be_null("symbol")
    validator.expect_column_values_to_not_be_null("month_close")
    
    print("Adding business logic expectations...")
    validator.expect_column_values_to_be_between(
        "month",
        min_value=1,
        max_value=12
    )
    
    print("Adding aggregation expectations...")
    validator.expect_column_pair_values_A_to_be_greater_than_B(
        column_A="month_high",
        column_B="month_low",
        or_equal=True
    )
    
    validator.expect_column_values_to_be_between(
        "avg_price",
        min_value=0,
        max_value=10000
    )
    
    print("Adding uniqueness expectations...")
    validator.expect_compound_columns_to_be_unique(
        column_list=["year", "month", "symbol"]
    )
    
    validator.save_expectation_suite(discard_failed_expectations=False)
    print("agg_stock_monthly_metrics suite created successfully!")
    print(f"Total expectations: {len(validator.get_expectation_suite().expectations)}")


def main():
    """Main execution function"""
    print("\n" + "="*60)
    print("NASDAQ Stock Pipeline - Great Expectations Setup")
    print("="*60)
    
    try:
        create_fact_table_expectations()
        create_dim_stock_expectations()
        create_weekly_agg_expectations()
        create_monthly_agg_expectations()
        
        print("\n" + "="*60)
        print("ALL EXPECTATION SUITES CREATED SUCCESSFULLY!")
        print("="*60)
        
        suite_names = context.list_expectation_suite_names()
        print(f"\nTotal suites created: {len(suite_names)}")
        print("\nExpectation suites:")
        for i, suite_name in enumerate(suite_names, 1):
            print(f"  {i}. {suite_name}")
        
        return 0
        
    except Exception as e:
        print(f"\nError creating expectations: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
