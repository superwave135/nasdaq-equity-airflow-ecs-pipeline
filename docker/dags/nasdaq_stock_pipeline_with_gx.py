"""
NASDAQ Stock Pipeline with Great Expectations Data Quality Validation
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.lambda_function import LambdaInvokeFunctionOperator
import great_expectations as gx
import json

# Default arguments
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def setup_gx_expectations(**context):
    """
    Setup Great Expectations expectation suites if they don't exist.
    This task ensures all required expectation suites are available before validation.
    """
    import os
    import subprocess
    
    # Initialize GX context
    context_root = os.getenv('GX_DATA_CONTEXT_ROOT_DIR', '/opt/airflow/great_expectations')
    gx_context = gx.get_context(context_root_dir=context_root)
    
    # Check if expectation suites exist
    suites = gx_context.list_expectation_suite_names()
    
    expected_suites = [
        'fact_stock_daily_price_suite',
        'dim_stock_suite',
        'agg_stock_weekly_metrics_suite',
        'agg_stock_monthly_metrics_suite'
    ]
    
    missing_suites = [suite for suite in expected_suites if suite not in suites]
    
    if missing_suites:
        print(f"Missing expectation suites: {missing_suites}")
        print(f"Running create_expectations.py to generate them...")
        
        # Run the script to create expectations
        script_path = '/opt/airflow/scripts/create_expectations.py'
        if os.path.exists(script_path):
            result = subprocess.run(['python', script_path], capture_output=True, text=True)
            print(result.stdout)
            if result.returncode != 0:
                print(f"Warning: Could not create all expectations")
                print(f"Error: {result.stderr}")
                print(f"Continuing anyway - expectations will be created on first validation")
        else:
            print(f"Script not found: {script_path}")
    else:
        print(f"All expectation suites exist: {suites}")
    
    return True

def run_gx_checkpoint(checkpoint_name: str, **context):
    """
    Run a Great Expectations checkpoint to validate data quality.
    
    Args:
        checkpoint_name: Name of the checkpoint to run
        context: Airflow context with execution_date
    
    Raises:
        Exception: If validation fails
    """
    import os
    from datetime import datetime, timedelta
    
    # Initialize GX context
    context_root = os.getenv('GX_DATA_CONTEXT_ROOT_DIR', '/opt/airflow/great_expectations')
    gx_context = gx.get_context(context_root_dir=context_root)
    
    # Get execution date and calculate processing date (T-1)
    execution_date = context['execution_date']
    if isinstance(execution_date, str):
        execution_date = datetime.fromisoformat(execution_date.replace('Z', '+00:00'))
    
    # Use T-1 for processing_date to match Lambda's logic
    processing_date_dt = execution_date - timedelta(days=1)
    processing_date = processing_date_dt.strftime('%Y-%m-%d')
    
    print(f"="*70)
    print(f"Running Great Expectations Checkpoint: {checkpoint_name}")
    print(f"Execution Date: {execution_date}")
    print(f"Processing Date (T-1): {processing_date}")
    print(f"="*70)
    
    try:
        # Get the checkpoint
        checkpoint = gx_context.get_checkpoint(checkpoint_name)
        
        # Build custom batch request with the processing date
        if checkpoint_name == 'daily_fact_validation':
            batch_request = {
                'datasource_name': 'nasdaq_athena_datasource',
                'data_connector_name': 'default_runtime_data_connector',
                'data_asset_name': 'fact_stock_daily_price',
                'runtime_parameters': {
                    # 'query': f"SELECT * FROM nasdaq_airflow_warehouse_dev.fact_stock_daily_price WHERE processing_date = DATE '{processing_date}'"
                    'query': f"SELECT * FROM nasdaq_airflow_warehouse_dev.fact_stock_daily_price WHERE processing_date LIKE '{processing_date}%'"
                },
                'batch_identifiers': {
                    'default_identifier_name': f'daily_validation_{processing_date}'
                }
            }
            
            # Run checkpoint with custom batch request
            result = checkpoint.run(
                validations=[{
                    'batch_request': batch_request,
                    'expectation_suite_name': 'fact_stock_daily_price_suite'
                }]
            )
        else:
            # For other checkpoints, run normally
            result = checkpoint.run()
        
        # Check if validation passed
        if result.success:
            print(f"Data Quality Validation PASSED for {checkpoint_name}")
            
            # Print summary
            validation_results = result.list_validation_results()
            print(f"   Total validations: {len(validation_results)}")
            
            for val_result in validation_results:
                stats = val_result.statistics
                print(f"   - {stats['evaluated_expectations']} expectations evaluated")
                print(f"   - {stats['successful_expectations']} succeeded")
                print(f"   - {stats['unsuccessful_expectations']} failed")
                print(f"   - Success rate: {stats['success_percent']:.2f}%")
            
            return True
        else:
            print(f"Data Quality Validation FAILED for {checkpoint_name}")
            
            # Print detailed failure information
            validation_results = result.list_validation_results()
            for val_result in validation_results:
                stats = val_result.statistics
                print(f"\nValidation Result:")
                print(f"   Total expectations: {stats['evaluated_expectations']}")
                print(f"   Successful: {stats['successful_expectations']}")
                print(f"   Failed: {stats['unsuccessful_expectations']}")
                print(f"   Success rate: {stats['success_percent']:.2f}%")
                
                # Print failed expectations
                print(f"\n   Failed Expectations:")
                for expectation_result in val_result.results:
                    if not expectation_result.success:
                        expectation_type = expectation_result.expectation_config.expectation_type
                        print(f"   - {expectation_type}")
                        if hasattr(expectation_result, 'result') and expectation_result.result:
                            print(f"     Details: {expectation_result.result}")
            
            raise Exception(f"Data quality validation failed for {checkpoint_name}")
            
    except Exception as e:
        print(f"Error running checkpoint {checkpoint_name}: {str(e)}")
        raise

# Create the DAG
with DAG(
    'nasdaq_stock_pipeline_with_gx',
    default_args=default_args,
    description='NASDAQ Stock Data Pipeline with Great Expectations Quality Checks',
    schedule_interval='0 2 * * *',  # Run daily at 2 AM UTC (10 AM Singapore time)
    catchup=False,
    tags=['nasdaq', 'stock', 'data-quality', 'great-expectations'],
) as dag:

    # Task 1: Extract stock data using Lambda
    # Lambda will use its own T-1 logic internally
    extract_stock_data = LambdaInvokeFunctionOperator(
        task_id='extract_stock_data',
        function_name='nasdaq-airflow-stock-extractor-dev',
        payload=json.dumps({
            'execution_date': '{{ ds }}'  # Just for logging
        }),
        aws_conn_id='aws_default',
    )

    # Task 2: Build dimension tables
    build_stock_dimensions = GlueJobOperator(
        task_id='build_stock_dimensions',
        job_name='nasdaq-airflow-dimensions-dev',
        script_args={
            '--processing_date': '{{ macros.ds_add(ds, -1) }}',  # T-1 date
        },
        iam_role_name='nasdaq-airflow-ecs-glue-role-dev',
        aws_conn_id='aws_default',
    )

    # Task 3: Build fact tables
    build_fact_tables = GlueJobOperator(
        task_id='build_fact_tables',
        job_name='nasdaq-airflow-fact-dev',
        script_args={
            '--processing_date': '{{ macros.ds_add(ds, -1) }}',  # T-1 date
        },
        iam_role_name='nasdaq-airflow-ecs-glue-role-dev',
        aws_conn_id='aws_default',
    )

    # Task 4: Build aggregations
    build_aggregations = GlueJobOperator(
        task_id='build_aggregations',
        job_name='nasdaq-airflow-aggregations-dev',
        script_args={
            '--processing_date': '{{ macros.ds_add(ds, -1) }}',  # T-1 date
        },
        iam_role_name='nasdaq-airflow-ecs-glue-role-dev',
        aws_conn_id='aws_default',
    )

    # Task 5: Setup GX expectations (AFTER tables exist)
    setup_gx_expectations_task = PythonOperator(
        task_id='setup_gx_expectations',
        python_callable=setup_gx_expectations,
        provide_context=True,
    )

    # Task 6: Validate dimension table quality
    validate_dimensions_quality = PythonOperator(
        task_id='validate_dimensions_quality',
        python_callable=run_gx_checkpoint,
        op_kwargs={'checkpoint_name': 'dim_stock_validation'},
        provide_context=True,
    )

    # Task 7: Validate fact table quality
    validate_facts_quality = PythonOperator(
        task_id='validate_facts_quality',
        python_callable=run_gx_checkpoint,
        op_kwargs={'checkpoint_name': 'daily_fact_validation'},
        provide_context=True,
    )

    # Task 8: Validate weekly aggregation quality
    validate_weekly_agg_quality = PythonOperator(
        task_id='validate_weekly_agg_quality',
        python_callable=run_gx_checkpoint,
        op_kwargs={'checkpoint_name': 'weekly_agg_validation'},
        provide_context=True,
    )

    # Task 9: Validate monthly aggregation quality
    validate_monthly_agg_quality = PythonOperator(
        task_id='validate_monthly_agg_quality',
        python_callable=run_gx_checkpoint,
        op_kwargs={'checkpoint_name': 'monthly_agg_validation'},
        provide_context=True,
    )

    # Define task dependencies - build tables FIRST, then setup expectations, then validate
    (
        extract_stock_data
        >> build_stock_dimensions
        >> build_fact_tables
        >> build_aggregations
        >> setup_gx_expectations_task
        >> validate_dimensions_quality >> validate_facts_quality >> validate_weekly_agg_quality >> validate_monthly_agg_quality
    )
