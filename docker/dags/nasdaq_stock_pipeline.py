from airflow import DAG
from airflow.decorators import task
from datetime import datetime, timedelta
import boto3
import time
import logging
import json

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'nasdaq_stock_pipeline',
    default_args=default_args,
    description='NASDAQ Stock Data Pipeline',
    schedule_interval='0 2 * * *',  # Run daily at 2 AM UTC
    catchup=False,
    tags=['nasdaq', 'stock', 'etl'],
)

@task(task_id='extract_stock_data', dag=dag)
def extract_stock_data(**context):
    """Extract stock data using Lambda function"""
    logger = logging.getLogger(__name__)
    logger.info("="*80)
    logger.info("STARTING DATA EXTRACTION")
    logger.info("="*80)
    
    lambda_client = boto3.client('lambda', region_name='ap-southeast-1')
    
    # Get execution date - Lambda will handle the "yesterday" logic
    execution_date = context['ds']
    logger.info(f"Execution date: {execution_date}")
    
    payload = {
        "execution_date": execution_date,  # Send today's date
        "symbols": ["AAPL", "MSFT", "GOOGL", "AMZN", "META"]
    }
    
    try:
        response = lambda_client.invoke(
            FunctionName='nasdaq-airflow-stock-extractor-dev',
            InvocationType='RequestResponse',
            Payload=json.dumps(payload)
        )
        
        # Parse Lambda response to get the actual processing date
        import json as json_module
        response_payload = json_module.loads(response['Payload'].read())
        processing_date = response_payload.get('processing_date', 'unknown')
        
        logger.info(f"Lambda invoked successfully")
        logger.info(f"Status Code: {response['StatusCode']}")
        logger.info(f"Data written to partition: date={processing_date}")
        
        return {"status": "success", "processing_date": processing_date}
        
    except Exception as e:
        logger.error(f"ERROR in extract_stock_data: {str(e)}")
        raise

@task(task_id='build_fact_table', dag=dag)
def build_fact_table(**context):
    """Build fact table using Glue job"""
    logger = logging.getLogger(__name__)
    logger.info("="*80)
    logger.info("STARTING FACT TABLE BUILD")
    logger.info("="*80)
    
    glue_client = boto3.client('glue', region_name='ap-southeast-1')
    
    # Get the processing date from upstream task
    ti = context['ti']
    extract_result = ti.xcom_pull(task_ids='extract_stock_data')
    processing_date = extract_result.get('processing_date')
    
    logger.info(f"Processing date from extract task: {processing_date}")
    
    try:
        response = glue_client.start_job_run(
            JobName='nasdaq-airflow-fact-dev',
            Arguments={
                '--processing_date': processing_date
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Job started: {job_run_id}")
        
        # Wait for job completion
        max_attempts = 40
        attempt = 0
        
        logger.info("Waiting for job to complete...")
        while attempt < max_attempts:
            attempt += 1
            time.sleep(30)
            
            status_response = glue_client.get_job_run(
                JobName='nasdaq-airflow-fact-dev',
                RunId=job_run_id
            )
            
            status = status_response['JobRun']['JobRunState']
            logger.info(f"Attempt {attempt}/{max_attempts}: Job status = {status}")
            
            if status == 'SUCCEEDED':
                logger.info("Fact table build completed successfully")
                return {"status": "success", "job_run_id": job_run_id}
            elif status in ['FAILED', 'STOPPED', 'ERROR', 'TIMEOUT']:
                error_msg = status_response['JobRun'].get('ErrorMessage', 'No error message')
                logger.error(f"Job failed with status: {status}")
                logger.error(f"Error message: {error_msg}")
                raise Exception(f"Job failed with status: {status}")
        
        raise Exception("Job timeout - exceeded maximum wait time")
        
    except Exception as e:
        logger.error(f"ERROR in build_fact_table:")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"Error message: {str(e)}")
        raise

@task(task_id='build_dimensions', dag=dag)
def build_dimensions(**context):
    """Build dimension tables using Glue job"""
    logger = logging.getLogger(__name__)
    logger.info("="*80)
    logger.info("STARTING DIMENSIONS BUILD")
    logger.info("="*80)
    
    glue_client = boto3.client('glue', region_name='ap-southeast-1')
    
    # Get the processing date from upstream task
    ti = context['ti']
    extract_result = ti.xcom_pull(task_ids='extract_stock_data')
    processing_date = extract_result.get('processing_date')
    
    logger.info(f"Processing date from extract task: {processing_date}")
    
    try:
        response = glue_client.start_job_run(
            JobName='nasdaq-airflow-dimensions-dev',
            Arguments={
                '--processing_date': processing_date
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Job started: {job_run_id}")
        
        # Wait for job completion
        max_attempts = 40
        attempt = 0
        
        logger.info("Waiting for job to complete...")
        while attempt < max_attempts:
            attempt += 1
            time.sleep(30)
            
            status_response = glue_client.get_job_run(
                JobName='nasdaq-airflow-dimensions-dev',
                RunId=job_run_id
            )
            
            status = status_response['JobRun']['JobRunState']
            logger.info(f"Attempt {attempt}/{max_attempts}: Job status = {status}")
            
            if status == 'SUCCEEDED':
                logger.info("Dimensions build completed successfully")
                return {"status": "success", "job_run_id": job_run_id}
            elif status in ['FAILED', 'STOPPED', 'ERROR', 'TIMEOUT']:
                error_msg = status_response['JobRun'].get('ErrorMessage', 'No error message')
                logger.error(f"Job failed with status: {status}")
                logger.error(f"Error message: {error_msg}")
                raise Exception(f"Job failed with status: {status}")
        
        raise Exception("Job timeout - exceeded maximum wait time")
        
    except Exception as e:
        logger.error(f"ERROR in build_dimensions:")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"Error message: {str(e)}")
        raise

@task(task_id='build_aggregations', dag=dag)
def build_aggregations(**context):
    """Build aggregation tables using Glue job"""
    logger = logging.getLogger(__name__)
    logger.info("="*80)
    logger.info("STARTING AGGREGATIONS BUILD")
    logger.info("="*80)
    
    glue_client = boto3.client('glue', region_name='ap-southeast-1')
    
    # Get the processing date from upstream task
    ti = context['ti']
    extract_result = ti.xcom_pull(task_ids='extract_stock_data')
    processing_date = extract_result.get('processing_date')
    
    logger.info(f"Processing date from extract task: {processing_date}")
    
    try:
        response = glue_client.start_job_run(
            JobName='nasdaq-airflow-aggregations-dev',
            Arguments={
                '--processing_date': processing_date
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Job started: {job_run_id}")
        
        # Wait for job completion
        max_attempts = 40
        attempt = 0
        
        logger.info("Waiting for job to complete...")
        while attempt < max_attempts:
            attempt += 1
            time.sleep(30)
            
            status_response = glue_client.get_job_run(
                JobName='nasdaq-airflow-aggregations-dev',
                RunId=job_run_id
            )
            
            status = status_response['JobRun']['JobRunState']
            logger.info(f"Attempt {attempt}/{max_attempts}: Job status = {status}")
            
            if status == 'SUCCEEDED':
                logger.info("Aggregations build completed successfully")
                return {"status": "success", "job_run_id": job_run_id}
            elif status in ['FAILED', 'STOPPED', 'ERROR', 'TIMEOUT']:
                error_msg = status_response['JobRun'].get('ErrorMessage', 'No error message')
                logger.error(f"Job failed with status: {status}")
                logger.error(f"Error message: {error_msg}")
                raise Exception(f"Job failed with status: {status}")
        
        raise Exception("Job timeout - exceeded maximum wait time")
        
    except Exception as e:
        logger.error(f"ERROR in build_aggregations:")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"Error message: {str(e)}")
        raise

# Define task dependencies
extract = extract_stock_data()
fact = build_fact_table()
dims = build_dimensions()
aggs = build_aggregations()

extract >> [fact, dims] >> aggs