############################################################################
#...Azure Infrastructure Deployment for SD-WAN MultiRegion Routing Tests...#
#...Version 1.0............................................................#
#...Written by: Oliver Fischer.............................................#
#...Email: osf@cisco.com...................................................#
############################################################################

# --------------------------------------------------------------------------
# Define Azure as provider an use credentials as defined in terraform.tfvars
# --------------------------------------------------------------------------

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
  features {}
}
