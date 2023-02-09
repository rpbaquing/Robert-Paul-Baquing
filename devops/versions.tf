terraform {
  backend "gcs" {
    bucket = "toptal-tfstate"
    prefix = "terraform/state"
  }
  
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.51.0"
    }
  }
}