# terraform/modules/s3/main.tf
# S3 Bucket for NASDAQ Stock Pipeline Data

resource "aws_s3_bucket" "data_bucket" {
  bucket        = var.bucket_name
  force_destroy = true  # ← ADDED: Allow Terraform to delete bucket with objects
  
  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    Purpose     = "NASDAQ stock data storage"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket_lifecycle" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    id     = "delete_old_raw_data"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = 90  # Delete raw data after 90 days
    }
  }

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 30  # Delete logs after 30 days
    }
  }

  rule {
    id     = "delete_temp_data"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7  # Delete temp data after 7 days
    }
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ============================================================================
# OUTPUTS - CRITICAL!
# ============================================================================

output "bucket_name" {
  value       = aws_s3_bucket.data_bucket.id
  description = "Name of the S3 bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.data_bucket.arn
  description = "ARN of the S3 bucket"
}

output "bucket_domain_name" {
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
  description = "Domain name of the S3 bucket"
}

# Aliases for backward compatibility (single bucket design)
# Both data and scripts use the same bucket with different prefixes
output "data_bucket_name" {
  value       = aws_s3_bucket.data_bucket.id
  description = "Alias for bucket_name (data stored under /data/ prefix)"
}

output "data_bucket_arn" {
  value       = aws_s3_bucket.data_bucket.arn
  description = "Alias for bucket_arn (data bucket)"
}

output "scripts_bucket_name" {
  value       = aws_s3_bucket.data_bucket.id
  description = "Alias for bucket_name (scripts stored under /scripts/ prefix)"
}

output "scripts_bucket_arn" {
  value       = aws_s3_bucket.data_bucket.arn
  description = "Alias for bucket_arn (scripts bucket)"
}


# NOTE: Data Docs public access disabled because:
# 1. Great Expectations is using filesystem stores (not S3)
# 2. Public access block is enabled for security
# 3. Data Docs can be accessed via ECS tasks if needed
# 
# If you want to enable Data Docs on S3 later:
# 1. Switch GX config to use S3 stores
# 2. Modify public access block to allow specific paths
# 3. Uncomment the resources below
#
# # Enable static website hosting for Data Docs
# resource "aws_s3_bucket_website_configuration" "data_docs" {
#   bucket = aws_s3_bucket.data_bucket.id
#
#   index_document {
#     suffix = "index.html"
#   }
#
#   error_document {
#     key = "error.html"
#   }
# }
#
# # Public read access for Data Docs only
# resource "aws_s3_bucket_policy" "data_docs_public_read" {
#   bucket = aws_s3_bucket.data_bucket.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid       = "PublicReadDataDocs"
#         Effect    = "Allow"
#         Principal = "*"
#         Action    = "s3:GetObject"
#         Resource  = "${aws_s3_bucket.data_bucket.arn}/great_expectations/data_docs/*"
#       }
#     ]
#   })
# }