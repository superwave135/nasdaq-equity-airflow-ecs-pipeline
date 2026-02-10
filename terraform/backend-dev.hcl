bucket         = "nasdaq-airflow-bucket"
key            = "terraform/state/dev/terraform.tfstate"
region         = "ap-southeast-1"
encrypt        = true
dynamodb_table = "nasdaq-terraform-lock"

