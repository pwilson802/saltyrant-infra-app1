
resource "aws_s3_bucket" "console" {
  bucket = "salty-console-${var.environment}"

  tags = {
    Name        = "salty-console-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.console.id
  versioning_configuration {
    status = "Enabled"
  }
}