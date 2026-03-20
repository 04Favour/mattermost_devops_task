terraform {
    backend "s3" {
        bucket = "mattermost-devid-bucket"
        key = "workspace/terraform.tfstate"
        region = "us-east-1"
        use_lockfile = true
        encrypt = "true"
    }

    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }

    required_version = ">= 1.2"
}