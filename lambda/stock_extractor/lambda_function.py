"""Lambda function for extracting stock data from FMP"""
import json
import boto3
import time
import ssl  
from datetime import datetime, timezone, timedelta
from urllib.request import urlopen
from urllib.error import HTTPError, URLError

# Import variables from config
import config

s3_client = boto3.client('s3', region_name=config.AWS_REGION)
secrets_client = boto3.client('secretsmanager', region_name=config.AWS_REGION)

def get_api_key():
    """Retrieve API key from Secrets Manager"""
    try:
        secret_name = config.API_SECRET_NAME
        print(f"Retrieving secret: {secret_name}")
        
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        
        api_key = secret.get('api_key')
        print(f"API key retrieved successfully")
        return api_key
    except Exception as e:
        print(f"Could not retrieve API key from {config.API_SECRET_NAME}: {e}")
        return None

def get_jsonparsed_data(url):
    """Fetch and parse JSON data from URL"""
    try:
        # FIXED: Use default SSL context without certifi
        context = ssl.create_default_context()
        
        response = urlopen(url, timeout=10, context=context)
        data = response.read().decode("utf-8")
        return json.loads(data)
    except HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        return None
    except URLError as e:
        print(f"URL Error: {e.reason}")
        return None
    except Exception as e:
        print(f"Unexpected error: {e}")
        return None

def fetch_fmp_quote(symbol, api_key):
    """Fetch real-time quote from FMP API using stable endpoint"""
    try:
        # Use the stable endpoint that works
        url = f"https://financialmodelingprep.com/stable/quote?symbol={symbol}&apikey={api_key}"
        
        print(f"Fetching {symbol} from FMP...")
        quote_data = get_jsonparsed_data(url)
        
        if quote_data and len(quote_data) > 0:
            quote = quote_data[0]  # FMP returns a list with one item
            
            return {
                # Basic info
                'symbol': quote.get('symbol'),
                'name': quote.get('name', f"{symbol} Inc."),
                'exchange': quote.get('exchange', 'NASDAQ'),
                
                # Price info
                'price': float(quote.get('price', 0)),
                'open': float(quote.get('open', 0)),
                'previous_close': float(quote.get('previousClose', 0)),
                'day_low': float(quote.get('dayLow', 0)),
                'day_high': float(quote.get('dayHigh', 0)),
                'year_low': float(quote.get('yearLow', 0)),
                'year_high': float(quote.get('yearHigh', 0)),
                
                # Change info
                'change': float(quote.get('change', 0)),
                'change_percent': float(quote.get('changePercentage', 0)),
                
                # Volume and market info
                'volume': int(quote.get('volume', 0)),
                'market_cap': quote.get('marketCap'),
                
                # Moving averages
                'price_avg_50': float(quote.get('priceAvg50', 0)),
                'price_avg_200': float(quote.get('priceAvg200', 0)),
                
                # Timestamp
                'timestamp': quote.get('timestamp', int(time.time())),
                
                # Metadata
                'extraction_time': datetime.now(timezone.utc).isoformat(),
                'api_endpoint': 'stable'
            }
        else:
            print(f"No data returned for {symbol}")
            return None
            
    except Exception as e:
        print(f"Error fetching {symbol}: {e}")
        return None

def fetch_real_data(symbols, api_key):
    """Fetch real data from FMP API"""
    stock_data = []
    
    for i, symbol in enumerate(symbols):
        print(f"Fetching {i+1}/{len(symbols)}: {symbol}")
        quote = fetch_fmp_quote(symbol, api_key)
        
        if quote:
            stock_data.append(quote)
            print(f"Successfully fetched {symbol}: ${quote['price']}")
        else:
            print(f"Failed to fetch {symbol}")
        
        # Rate limiting (avoid hitting API limits)
        if i < len(symbols) - 1:  # Don't delay after last symbol
            time.sleep(config.RATE_LIMIT_DELAY)
    
    return stock_data

def generate_mock_data(symbols, trading_date_str):
    """Generate mock data for testing"""
    import random

    # Convert trading_date string to timestamp
    trading_dt = datetime.strptime(trading_date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
    trading_timestamp = int(trading_dt.timestamp())

    return [
        {
            'symbol': symbol,
            'name': f"{symbol} Inc.",
            'exchange': 'NASDAQ',
            'price': round(random.uniform(100, 500), 2),
            'open': round(random.uniform(100, 500), 2),
            'previous_close': round(random.uniform(100, 500), 2),
            'day_low': round(random.uniform(100, 500), 2),
            'day_high': round(random.uniform(100, 500), 2),
            'year_low': round(random.uniform(50, 200), 2),
            'year_high': round(random.uniform(300, 600), 2),
            'change': round(random.uniform(-10, 10), 2),
            'change_percent': round(random.uniform(-5, 5), 2),
            'volume': random.randint(500000, 2000000),
            'market_cap': random.randint(1000000000, 3000000000000),
            'price_avg_50': round(random.uniform(100, 500), 2),
            'price_avg_200': round(random.uniform(100, 500), 2),
            'timestamp': trading_timestamp,
            'extraction_time': datetime.now(timezone.utc).isoformat(),
            'api_endpoint': 'mock'
        }
        for symbol in symbols
    ]

def save_to_s3(data, trading_date_str):
    """Save data to S3 with trading_date in partition and filename"""
    now_utc = datetime.now(timezone.utc)
    
    # Use trading_date for BOTH partition AND filename
    # This ensures alignment: partition folder matches the data inside
    date_for_filename = trading_date_str.replace('-', '')  # YYYYMMDD format
    time_for_filename = now_utc.strftime('%H%M%S')
    
    # Log the date logic
    print("="*60)
    print("DATE CALCULATION (Lambda)")
    print("="*60)
    print(f"Extraction time (UTC): {now_utc.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Trading date (data date): {trading_date_str}")
    print(f"S3 Partition: raw/stock_quotes/date={trading_date_str}/")
    print(f"S3 Filename: stocks_{date_for_filename}_{time_for_filename}.jsonl")
    print("="*60)
    
    # Use .jsonl extension and JSONL format (newline-delimited JSON)
    key = f"raw/stock_quotes/date={trading_date_str}/stocks_{date_for_filename}_{time_for_filename}.jsonl"
    
    # Convert to JSONL format - one JSON object per line
    jsonl_content = '\n'.join([json.dumps(item) for item in data])
    
    s3_client.put_object(
        Bucket=config.S3_BUCKET,
        Key=key,
        Body=jsonl_content,
        ContentType='application/x-ndjson'
    )
    
    print(f"Data saved to s3://{config.S3_BUCKET}/{key}")
    print(f"Format: JSONL (newline-delimited JSON)")
    print(f"Records: {len(data)}")
    
    return {
        'key': key,
        'trading_date': trading_date_str
    }

def lambda_handler(event, context):
    """Main Lambda handler"""
    
    print(f"=== Stock Extractor Lambda ===")
    print(f"API Provider: {config.API_PROVIDER}")
    print(f"Mock Data Mode: {config.USE_MOCK_DATA}")
    print(f"S3 Bucket: {config.S3_BUCKET}")
    
    # ============================================================================
    # TRADING DATE CALCULATION
    # Always use T-1 logic: extract data for PREVIOUS trading day
    # This ensures data timestamp aligns with partition folder
    # ============================================================================
    now_utc = datetime.now(timezone.utc)
    
    # Calculate trading date as T-1 (previous day)
    # Note: This is simplified - doesn't account for weekends/holidays
    # For production, you'd want to check market calendar
    trading_date = now_utc - timedelta(days=1)
    trading_date_str = trading_date.strftime('%Y-%m-%d')
    
    print(f"Current time (UTC): {now_utc.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Trading date (T-1): {trading_date_str}")
    
    # Airflow's execution_date is stored for logging but NOT used for partitioning
    execution_date_from_airflow = event.get('execution_date', 'N/A')
    print(f"Airflow execution_date (for reference): {execution_date_from_airflow}")

    # Get stock symbols from event or use defaults
    symbols = event.get('symbols', config.DEFAULT_SYMBOLS)
    print(f"Symbols to fetch: {symbols}")
    
    # Get API key if not using mock data
    api_key = get_api_key()

    # Extract data from Mock or API
    if config.USE_MOCK_DATA or not api_key:
        print("Generating mock data...")
        stock_data = generate_mock_data(symbols, trading_date_str)
        data_source = 'MOCK'
    else:
        print(f"Fetching real data from FMP API (stable endpoint)...")
        stock_data = fetch_real_data(symbols, api_key)
        data_source = 'FMP_REAL'
        
        if not stock_data:
            print("Failed to fetch real data, falling back to mock data")
            stock_data = generate_mock_data(symbols, trading_date_str)
            data_source = 'MOCK_FALLBACK'
    
    # Save to S3 using trading_date for partition
    s3_result = save_to_s3(stock_data, trading_date_str)

    result = {
        'statusCode': 200,
        'trading_date': s3_result['trading_date'],  # This is what Airflow/Glue should use!
        'records_extracted': len(stock_data),
        'body': json.dumps({
            'records_extracted': len(stock_data),
            's3_location': f"s3://{config.S3_BUCKET}/{s3_result['key']}",
            'data_source': data_source,
            'api_provider': config.API_PROVIDER,
            'api_endpoint': 'stable',
            'symbols': symbols,
            'successful': len(stock_data),
            'failed': len(symbols) - len(stock_data),
            'trading_date': s3_result['trading_date'],
            'format': 'JSONL'
        })
    }
    
    print(f"=== Extraction Complete ===")
    print(f"Successfully extracted: {len(stock_data)}/{len(symbols)}")
    print(f"Trading date: {s3_result['trading_date']}")
    print(f"Output format: JSONL (newline-delimited JSON)")
    
    return result