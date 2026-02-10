#!/usr/bin/env python3
"""
Great Expectations Setup Validation Script
Tests GX configuration, Athena connectivity, and table access
"""
import os
import sys
from datetime import datetime
from typing import Dict, Any, List, Tuple

try:
    import great_expectations as gx
    from great_expectations.core.batch import RuntimeBatchRequest
    from great_expectations.data_context import FileDataContext
except ImportError as e:
    print(f"Failed to import Great Expectations: {e}")
    sys.exit(1)

# Configuration
CONTEXT_ROOT = "/opt/airflow/great_expectations"
DATASOURCE_NAME = "nasdaq_athena_datasource"
DATABASE_NAME = "nasdaq_airflow_warehouse_dev"

# Test tables from our pipeline
TEST_TABLES = [
    "fact_stock_daily_price",
    "dim_stock",
    "agg_stock_weekly_metrics",
    "agg_stock_monthly_metrics",
]

def print_header(title: str, level: int = 1):
    """Print formatted section header"""
    if level == 1:
        print("\n" + "=" * 70)
        print(f"  {title}")
        print("=" * 70)
    else:
        print("\n" + "=" * 60)
        print(f"{title}")
        print("=" * 60)

def print_result(test_name: str, passed: bool, message: str = ""):
    """Print test result with emoji"""
    status = "Pass" if passed else "Fail"
    print(f"{status} {test_name:<30} {message}")

def test_context_initialization() -> Tuple[bool, Any]:
    """Test 1: Initialize GX context"""
    print_header("TEST 1: Context Initialization", level=2)
    print(f"Context root: {CONTEXT_ROOT}")
    
    try:
        context = gx.get_context(context_root_dir=CONTEXT_ROOT)
        
        config_version = context.project_config_with_variables_substituted.config_version
        datasources = list(context.list_datasources())
        
        print(f"GX context initialized successfully")
        print(f"Config version: {config_version}")
        print(f"Datasources: {datasources}")
        
        return True, context
        
    except Exception as e:
        print(f"Context initialization failed: {e}")
        return False, None

def test_datasource_connection(context) -> Tuple[bool, Any]:
    """Test 2: Verify Athena datasource exists and is accessible"""
    print_header("TEST 2: Athena Datasource Connection", level=2)
    
    try:
        datasource = context.get_datasource(DATASOURCE_NAME)
        
        engine_type = type(datasource.execution_engine).__name__
        
        print(f"Datasource retrieved successfully")
        print(f"Datasource name: {DATASOURCE_NAME}")
        print(f"Execution engine: {engine_type}")
        
        return True, datasource
        
    except Exception as e:
        print(f"Datasource connection failed: {e}")
        return False, None

def test_athena_query(context, datasource) -> bool:
    """Test 3: Execute a simple query against Athena"""
    print_header("TEST 3: Athena Query Execution", level=2)
    
    try:
        # Simple query to test connectivity
        batch_request = RuntimeBatchRequest(
            datasource_name=DATASOURCE_NAME,
            data_connector_name="default_runtime_data_connector",
            data_asset_name="test_query",
            runtime_parameters={
                "query": f"SELECT 1 as test_column"
            },
            batch_identifiers={"default_identifier_name": "test_batch"}
        )
        
        # Create a temporary expectation suite
        suite_name = "temp_test_suite"
        context.add_or_update_expectation_suite(expectation_suite_name=suite_name)
        
        # Get validator
        validator = context.get_validator(
            batch_request=batch_request,
            expectation_suite_name=suite_name
        )
        
        # For SQL validators, we can't access the dataframe directly
        # Instead, execute a simple expectation to verify the query works
        result = validator.expect_column_to_exist("test_column")
        
        if result.success:
            print(f"Athena query executed successfully")
            print(f"Query returned expected column: test_column")
            return True
        else:
            print(f"Athena query validation failed")
            return False
        
    except Exception as e:
        print(f"Athena query failed: {e}")
        return False

def test_table_access(context) -> Dict[str, bool]:
    """Test 4: Verify access to NASDAQ tables"""
    print_header("TEST 4: NASDAQ Table Access", level=2)
    
    results = {}
    
    for table_name in TEST_TABLES:
        try:
            # Create batch request for the table
            batch_request = RuntimeBatchRequest(
                datasource_name=DATASOURCE_NAME,
                data_connector_name="default_runtime_data_connector",
                data_asset_name=table_name,
                runtime_parameters={
                    "query": f"SELECT * FROM {DATABASE_NAME}.{table_name} LIMIT 1"
                },
                batch_identifiers={"default_identifier_name": f"{table_name}_batch"}
            )
            
            # Create expectation suite for this table
            suite_name = f"temp_{table_name}_suite"
            context.add_or_update_expectation_suite(expectation_suite_name=suite_name)
            
            # Get validator
            validator = context.get_validator(
                batch_request=batch_request,
                expectation_suite_name=suite_name
            )
            
            # Try to get row count (this will execute the query)
            row_count_result = validator.expect_table_row_count_to_be_between(
                min_value=0,
                max_value=1000000
            )
            
            if row_count_result.success:
                print_result(table_name, True, "- Accessible ✓")
                results[table_name] = True
            else:
                print_result(table_name, False, f"- Validation failed")
                results[table_name] = False
            
        except Exception as e:
            error_msg = str(e)[:60] + "..." if len(str(e)) > 60 else str(e)
            print_result(table_name, False, f"- Error: {error_msg}")
            results[table_name] = False
    
    return results

def test_stores_configuration(context) -> bool:
    """Test 5: Verify store configurations"""
    print_header("TEST 5: Stores Configuration", level=2)
    
    try:
        stores = context.stores
        
        print(f"Total stores configured: {len(stores)}")
        
        for store_name, store in stores.items():
            store_class = type(store).__name__
            backend_class = type(store.store_backend).__name__ if hasattr(store, 'store_backend') else 'N/A'
            
            print(f"Store: {store_name}")
            print(f"Class: {store_class}")
            print(f"Backend: {backend_class}")
        
        print(f"Stores configured correctly")
        return True
        
    except Exception as e:
        print(f"Store configuration check failed: {e}")
        return False

def test_expectation_suites(context) -> bool:
    """Test 6: List available expectation suites"""
    print_header("TEST 6: Expectation Suites", level=2)
    
    try:
        suites = context.list_expectation_suite_names()
        
        if suites:
            print(f"Found {len(suites)} expectation suite(s):")
            for i, suite_name in enumerate(suites, 1):
                print(f"   {i}. {suite_name}")
        else:
            print(f"No expectation suites found (this is OK for initial setup)")
        
        return True
        
    except Exception as e:
        print(f"Failed to list expectation suites: {e}")
        return False

def run_all_tests() -> bool:
    """Run all tests and return overall success status"""
    print_header("GREAT EXPECTATIONS SETUP TEST SUITE")
    print("  NASDAQ Stock Data Pipeline")
    print("=" * 70)
    print(f"\nTest run: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Track results
    test_results = {}
    
    # Test 1: Context initialization
    context_pass, context = test_context_initialization()
    test_results['context_init'] = context_pass
    
    if not context_pass:
        print("\nCRITICAL: Context initialization failed. Stopping tests.")
        return False
    
    # Test 2: Datasource connection
    datasource_pass, datasource = test_datasource_connection(context)
    test_results['datasource'] = datasource_pass
    
    if not datasource_pass:
        print("\nWARNING: Datasource connection failed. Skipping query tests.")
        query_pass = False
        table_pass = False
    else:
        # Test 3: Athena query
        query_pass = test_athena_query(context, datasource)
        test_results['athena_query'] = query_pass
        
        # Test 4: Table access
        table_results = test_table_access(context)
        table_pass = all(table_results.values())
        test_results['table_access'] = table_pass
    
    # Test 5: Stores configuration
    stores_pass = test_stores_configuration(context)
    test_results['s3_stores'] = stores_pass
    
    # Test 6: Expectation suites
    suites_pass = test_expectation_suites(context)
    test_results['expectation_suites'] = suites_pass
    
    # Print summary
    print_header("TEST SUMMARY")
    
    for test_name, passed in test_results.items():
        status = "PASS" if passed else "FAIL"
        print(f"{status:12} - {test_name}")
    
    passed_count = sum(test_results.values())
    total_count = len(test_results)
    
    print(f"\nResults: {passed_count}/{total_count} tests passed")
    
    if passed_count == total_count:
        print("\nALL TESTS PASSED!")
        print("Great Expectations is properly configured and ready to use.")
        return True
    elif passed_count >= total_count - 2:
        print("\nSOME TESTS FAILED")
        print("Please review the errors above and fix configuration issues.")
        return False
    else:
        print("\nMULTIPLE TESTS FAILED")
        print("Please check your GX configuration and AWS credentials.")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)