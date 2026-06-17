# Remote state for the Azure stack. Fill the TODO values, then `terraform init`.
# Use a storage account in the connectivity/management subscription.
terraform {
  backend "azurerm" {
    resource_group_name  = "TODO-rg-tfstate"          # TODO: pre-created
    storage_account_name = "TODOhybridtfstate"        # TODO: globally unique, 3-24 lc alnum
    container_name       = "tfstate"
    key                  = "stacks/azure/terraform.tfstate"
  }
}
