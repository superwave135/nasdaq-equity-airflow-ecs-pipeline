"""
Test Great Expectations in Production ECS Environment
This DAG validates that GX works with AWS credentials via IAM roles
"""
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta
import great_expectations as gx
from great_expectations.core.batch import RuntimeBatchRequest

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def test_gx_context():
    """Test GX context initialization"""
    print("=" * 70)
    print("Testing Great Expectations Context Initialization")
    print("=" * 70)
    
    context = gx.get_context(context_root_dir="/opt/airflow/great_expectations")
    
    print(f"Context initialized")
    print(f"Config version: {context.project_config_with_variables_substituted.config_version}")
    print(f"Datasources: {list(context.list_datasources())}")
    
    return "context_initialized"

def test_athena_connection():
    """Test Athena connection with IAM role credentials"""
    print("=" * 70)
    print("Testing Athena Connection")
    print("=" * 70)
    
    context = gx.get_context(context_root_dir="/opt/airflow/great_expectations")
    datasource = context.get_datasource("nasdaq_athena_datasource")
    
    print(f"Datasource retrieved: {datasource.name}")
    
    # Test simple query
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="connection_test",
        runtime_parameters={
            "query": "SELECT 1 as test_column"
        },
        batch_identifiers={"default_identifier_name": "test"}
    )
    
    context.add_or_update_expectation_suite(expectation_suite_name="test_suite")
    
    validator = context.get_validator(
        batch_request=batch_request,
        expectation_suite_name="test_suite"
    )
    
    result = validator.expect_column_to_exist("test_column")
    
    if result.success:
        print("Athena query executed successfully")
        return "athena_connection_success"
    else:
        raise Exception("Athena query validation failed")

def test_table_query():
    """Test querying actual NASDAQ tables"""
    print("=" * 70)
    print("Testing NASDAQ Table Query")
    print("=" * 70)
    
    context = gx.get_context(context_root_dir="/opt/airflow/great_expectations")
    
    # Query fact_stock_daily_price
    batch_request = RuntimeBatchRequest(
        datasource_name="nasdaq_athena_datasource",
        data_connector_name="default_runtime_data_connector",
        data_asset_name="fact_stock_daily_price",
        runtime_parameters={
            "query": """
                SELECT * 
                FROM nasdaq_airflow_warehouse_dev.fact_stock_daily_price 
                LIMIT 5
            """
        },
        batch_identifiers={"default_identifier_name": "fact_test"}
    )
    
    context.add_or_update_expectation_suite(expectation_suite_name="fact_test_suite")
    
    validator = context.get_validator(
        batch_request=batch_request,
        expectation_suite_name="fact_test_suite"
    )
    
    # Test that we can query the table
    result = validator.expect_table_row_count_to_be_between(min_value=0, max_value=100000)
    
    if result.success:
        print("fact_stock_daily_price table accessible")
        return "table_query_success"
    else:
        raise Exception("Table query validation failed")

with DAG(
    'test_gx_production',
    default_args=default_args,
    description='Test Great Expectations in production ECS environment',
    schedule_interval=None,  # Manual trigger only
    catchup=False,
    tags=['test', 'great_expectations'],
) as dag:
    
    task_test_context = PythonOperator(
        task_id='test_gx_context',
        python_callable=test_gx_context,
    )
    
    task_test_athena = PythonOperator(
        task_id='test_athena_connection',
        python_callable=test_athena_connection,
    )
    
    task_test_table = PythonOperator(
        task_id='test_table_query',
        python_callable=test_table_query,
    )
    
    task_test_context >> task_test_athena >> task_test_table

