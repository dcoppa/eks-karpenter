terraform {
  backend "s3" {
    bucket         = "terraform-state-dcoppa"
    key            = "terraform-dcoppa-cluster.state"
    dynamodb_table = "terraform-state-dcoppa-lock"
    region         = "eu-central-1"
  }
}
