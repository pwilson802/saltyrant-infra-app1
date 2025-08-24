
resource "aws_s3_bucket" "console" {
  bucket = "salty-console-${var.environment}"

  tags = {
    Name        = "salty-console-${var.environment}"
    Environment = var.environment
  }
}