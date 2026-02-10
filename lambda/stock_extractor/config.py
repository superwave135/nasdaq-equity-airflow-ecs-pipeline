# lambda/stock_extractor/config.py
# """Configuration for stock extractor"""
# import os
# AWS_REGION = os.environ.get('AWS_REGION', 'ap-southeast-1')
# S3_BUCKET = os.environ.get('S3_BUCKET')
# API_PROVIDER = os.environ.get('API_PROVIDER', 'fmp_api_key')

"""Configuration for stock extractor"""
import os

# AWS Configuration
AWS_REGION = os.environ.get('AWS_REGION', 'ap-southeast-1')
S3_BUCKET = os.environ.get('S3_BUCKET')

# API Configuration
# API_SECRET_NAME = os.environ.get('API_SECRET_NAME', 'nasdaq-pipeline/stock-api-key')
API_SECRET_NAME = os.environ.get('API_SECRET_NAME', 'nasdaq-pipeline/stock-api-key')
API_PROVIDER = os.environ.get('API_PROVIDER', 'fmp')  # Changed to 'fmp'

# Default stock symbols to fetch
DEFAULT_SYMBOLS = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'META']

# Mock data mode (set to False when using real API)
# USE_MOCK_DATA = os.environ.get('USE_MOCK_DATA', 'true').lower() == 'true'

# Mock data mode (default: False, set to True explicitly via env var)
USE_MOCK_DATA = os.environ.get("USE_MOCK_DATA", 'false').strip().lower() in ("1", "true", "yes")

# FMP API Configuration
FMP_BASE_URL = 'https://financialmodelingprep.com/api/v3'

# Rate limiting for FMP (Free tier: 250 calls/day)
RATE_LIMIT_DELAY = float(os.environ.get('RATE_LIMIT_DELAY', '1'))  # 1 second between calls
