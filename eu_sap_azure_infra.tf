# --------------------------------------------------------------------------
# Create Ressource Group
# --------------------------------------------------------------------------

resource "azurerm_resource_group" "rg_eu" {
  name     = "osf_rg_sap_eu"
  location = "Germany West Central"

  tags = {
    name = "osf_sap"
  }
}

# --------------------------------------------------------------------------
# Create Europe NSG which is shared across all vNets in Europe
# This Rule will allow SSH, HTTP and HTTPS
# --------------------------------------------------------------------------

resource "azurerm_network_security_group" "eu_nsg" {
  name                = "eu-nsg"
  location            = azurerm_resource_group.rg_eu.location
  resource_group_name = azurerm_resource_group.rg_eu.name

  tags = {
    name = "osf_sap"
  }
}
resource "azurerm_network_security_rule" "eu_nsg_rule" {
  for_each                    = local.nsg_rules
  name                        = each.key
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = azurerm_resource_group.rg_eu.name
  network_security_group_name = azurerm_network_security_group.eu_nsg.name
}

# --------------------------------------------------------------------------
#           ******** Create eu_transit_vnet environment ********
# --------------------------------------------------------------------------

# ---------- Create eu_transit_vnet (HUB) ----------
resource "azurerm_virtual_network" "eu_transit_vnet" {
  name                = "eu-transit-vnet"
  resource_group_name = azurerm_resource_group.rg_eu.name
  location            = azurerm_resource_group.rg_eu.location
  address_space       = ["10.2.2.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_transit_subnet (HUB) ----------
resource "azurerm_subnet" "eu_transit_subnet1" {
  name                 = "eu-transit-subnet1"
  resource_group_name  = azurerm_resource_group.rg_eu.name
  virtual_network_name = azurerm_virtual_network.eu_transit_vnet.name
  address_prefixes     = ["10.2.2.0/24"]
}
# ---------- Create network interface nic (HUB) ----------
resource "azurerm_network_interface" "eu_transit_subnet_nic_1" {
  name                 = "eu-transit-subnet-nic-1"
  location             = azurerm_resource_group.rg_eu.location
  resource_group_name  = azurerm_resource_group.rg_eu.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.eu_transit_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.eu_hub_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (HUB) ----------
resource "azurerm_virtual_machine" "eu_hub_vm" {
  name                          = "eu-hub-vm"
  resource_group_name           = azurerm_resource_group.rg_eu.name
  location                      = azurerm_resource_group.rg_eu.location
  primary_network_interface_id  = azurerm_network_interface.eu_transit_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.eu_transit_subnet_nic_1.id]
  vm_size                       = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "eu-hub-vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "eu-hub-vm-1"
    admin_username = var.vm_username
    admin_password = var.vm_password
    custom_data    = file("cloud-init.sh")
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    name = "osf_sap"
  }
}

# --------------------------------------------------------------------------
# Creating Route Table for HUB
# --------------------------------------------------------------------------

# ---------- Create UDR on hub to route to app1 and app2 (HUB) ----------
resource "azurerm_route_table" "eu_user_defined_route_table_hub" {
  name                          = "eu-user-defined-route-table_hub"
  location                      = azurerm_resource_group.rg_eu.location
  resource_group_name           = azurerm_resource_group.rg_eu.name
  disable_bgp_route_propagation = false

  # route {
  #   name           = "udr_hub_to_spoke1"
  #   address_prefix = "10.2.3.0/24"
  #   next_hop_type  = "vnetlocal"
  #   #next_hop_in_ip_address = "vnetlocal"
  # }

  tags = {
    name = "osf_sap"
  }
}
# ---------- Associate eu_hub route table (HUB) ----------
resource "azurerm_subnet_route_table_association" "eu_rt_hub" {
  subnet_id      = azurerm_subnet.eu_transit_subnet1.id
  route_table_id = azurerm_route_table.eu_user_defined_route_table_hub.id
}
# --------------------------------------------------------------------------
# Application_1 network configuration
# --------------------------------------------------------------------------

# ---------- Create eu_app_1 virtual network (SPOKE1) ----------
resource "azurerm_virtual_network" "eu_app_1" {
  name                = "eu-app-1"
  resource_group_name = azurerm_resource_group.rg_eu.name
  location            = "France Central"
  address_space       = ["10.2.3.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_1 subnet (SPOKE1) ----------
resource "azurerm_subnet" "eu_app1_subnet1" {
  name                 = "eu-app1-subnet1"
  resource_group_name  = azurerm_resource_group.rg_eu.name
  virtual_network_name = azurerm_virtual_network.eu_app_1.name
  address_prefixes     = ["10.2.3.0/24"]
}
# ---------- Create network interface nic (SPOKE1) ----------
resource "azurerm_network_interface" "eu_spoke1_subnet_nic_1" {
  name                 = "eu-spoke1-subnet-nic-1"
  resource_group_name  = azurerm_resource_group.rg_eu.name
  location             = "France Central"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.eu_app1_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.eu_spoke1_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (SPOKE1) ----------
resource "azurerm_virtual_machine" "eu_spoke1_vm" {
  name                          = "eu-spoke1-vm"
  resource_group_name           = azurerm_resource_group.rg_eu.name
  location                      = "France Central"
  primary_network_interface_id  = azurerm_network_interface.eu_spoke1_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.eu_spoke1_subnet_nic_1.id]
  vm_size                       = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "spoke1-vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "spoke1-vm-1"
    admin_username = var.vm_username
    admin_password = var.vm_password
    custom_data    = file("cloud-init.sh")
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Route Table for SPOKE1 ----------
resource "azurerm_route_table" "eu_user_defined_route_table_spoke1" {
  name                          = "eu-user-defined-route-table-spoke1"
  location                      = "France Central"
  resource_group_name           = azurerm_resource_group.rg_eu.name
  disable_bgp_route_propagation = false

# ---------- Spoke should forward all traffic with 10 to NVA ----------
  route {
    name                   = "to_spoke2"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.eu_transit_subnet_nic_1.private_ip_address
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Associate eu_app_1 route table (SPOKE1) ----------
resource "azurerm_subnet_route_table_association" "eu_rt_spoke1" {
  subnet_id      = azurerm_subnet.eu_app1_subnet1.id
  route_table_id = azurerm_route_table.eu_user_defined_route_table_spoke1.id
}

# --------------------------------------------------------------------------
# Application_2 network configuration
# --------------------------------------------------------------------------

# ---------- Create eu_app_2 virtual network (SPOKE2) ----------
resource "azurerm_virtual_network" "eu_app_2" {
  name                = "eu-app-2"
  resource_group_name = azurerm_resource_group.rg_eu.name
  location            = "UK South"
  address_space       = ["10.2.4.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_2 subnet (SPOKE2) ----------
resource "azurerm_subnet" "eu_app2_subnet1" {
  name                 = "eu-app2-subnet1"
  resource_group_name  = azurerm_resource_group.rg_eu.name
  virtual_network_name = azurerm_virtual_network.eu_app_2.name
  address_prefixes     = ["10.2.4.0/24"]
}
# ---------- Create network interface nic (SPOKE2) ----------
resource "azurerm_network_interface" "eu_spoke2_subnet_nic_1" {
  name                 = "eu-spoke2-subnet-nic-1"
  resource_group_name  = azurerm_resource_group.rg_eu.name
  location             = "UK South"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.eu_app2_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.eu_spoke2_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (SPOKE2) ----------
resource "azurerm_virtual_machine" "eu_spoke2_vm" {
  name                          = "eu-spoke2-vm"
  resource_group_name           = azurerm_resource_group.rg_eu.name
  location                      = "UK South"
  primary_network_interface_id  = azurerm_network_interface.eu_spoke2_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.eu_spoke2_subnet_nic_1.id]
  vm_size                       = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "eu-spoke2-vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "eu-spoke2-vm-1"
    admin_username = var.vm_username
    admin_password = var.vm_password
    custom_data    = file("cloud-init.sh")
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Route Table for SPOKE2 ----------
resource "azurerm_route_table" "eu_user_defined_route_table_spoke2" {
  name                          = "eu-user-defined-route-table-spoke2"
  location                      = "UK South"
  resource_group_name           = azurerm_resource_group.rg_eu.name
  disable_bgp_route_propagation = false

# ---------- Spoke should forward all traffic with 10 to NVA ----------
  route {
    name                   = "to_spoke1"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.eu_transit_subnet_nic_1.private_ip_address
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_1 route table (SPOKE2) ----------
resource "azurerm_subnet_route_table_association" "eu_rt_spoke2" {
  subnet_id      = azurerm_subnet.eu_app2_subnet1.id
  route_table_id = azurerm_route_table.eu_user_defined_route_table_spoke2.id
}

# --------------------------------------------------------------------------
# Create Global vNet peering for EU transit_vnet and application layer
# --------------------------------------------------------------------------

# ---------- Create vnet peering between Hub and SPOKE1 ----------
resource "azurerm_virtual_network_peering" "eu_hub_2_eu_app_1" {
  name                         = "eu-hub-2-eu-app-1"
  resource_group_name          = azurerm_resource_group.rg_eu.name
  virtual_network_name         = azurerm_virtual_network.eu_transit_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.eu_app_1.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}
# ---------- Create vnet peering between SPOKE1 and HUB ----------
resource "azurerm_virtual_network_peering" "eu_app_1_2_eu_hub" {
  name                         = "eu-app-1-2-eu-hub"
  resource_group_name          = azurerm_resource_group.rg_eu.name
  virtual_network_name         = azurerm_virtual_network.eu_app_1.name
  remote_virtual_network_id    = azurerm_virtual_network.eu_transit_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
# ---------- Create vnet peering between Hub and SPOKE2 ----------
resource "azurerm_virtual_network_peering" "eu_hub_2_eu_app_2" {
  name                         = "eu-hub-2-eu-app-2"
  resource_group_name          = azurerm_resource_group.rg_eu.name
  virtual_network_name         = azurerm_virtual_network.eu_transit_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.eu_app_2.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}
# ---------- Create vnet peering between SPOKE2 and Hub ----------
resource "azurerm_virtual_network_peering" "eu_app_2_2_eu_hub" {
  name                         = "eu-app-2-2-eu-hub"
  resource_group_name          = azurerm_resource_group.rg_eu.name
  virtual_network_name         = azurerm_virtual_network.eu_app_2.name
  remote_virtual_network_id    = azurerm_virtual_network.eu_transit_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# --------------------------------------------------------------------------
# Create Public IP (pip) for host in eu_transit_subnet1
# --------------------------------------------------------------------------

# ---------- Create Public Inetner IP for Hub VM ----------
resource "azurerm_public_ip" "eu_hub_pip" {
  name                = "eu-hub-pip"
  location            = azurerm_resource_group.rg_eu.location
  resource_group_name = azurerm_resource_group.rg_eu.name
  allocation_method   = "Dynamic"

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Public Inetner IP for Spoke1 VM ----------
resource "azurerm_public_ip" "eu_spoke1_pip" {
  name                = "eu-spoke1-pip"
  location            = "France Central"
  resource_group_name = azurerm_resource_group.rg_eu.name
  allocation_method   = "Dynamic"

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Public Inetner IP for Spoke2 VM ----------
resource "azurerm_public_ip" "eu_spoke2_pip" {
  name                = "eu-spoke2-pip"
  location            = "UK South"
  resource_group_name = azurerm_resource_group.rg_eu.name
  allocation_method   = "Dynamic"

  tags = {
    name = "osf_sap"
  }
}

# --------------------------------------------------------------------------
# Print public and private IP addresses of VMs
# --------------------------------------------------------------------------

# Azure is not assigning public ip in upfront. You need to write the 
# dependency in data and then in order to show as output!
data "azurerm_public_ip" "eu_hub_pip" {
  name = "eu-hub-pip"
  resource_group_name = azurerm_resource_group.rg_eu.name
  depends_on = [azurerm_virtual_machine.eu_hub_vm]
}
data "azurerm_public_ip" "eu_spoke1_pip" {
  name = "eu-spoke1-pip"
  resource_group_name = azurerm_resource_group.rg_eu.name
  depends_on = [azurerm_virtual_machine.eu_spoke1_vm]
}
data "azurerm_public_ip" "eu_spoke2_pip" {
  name = "eu-spoke2-pip"
  resource_group_name = azurerm_resource_group.rg_eu.name
  depends_on = [azurerm_virtual_machine.eu_spoke2_vm]
}

output "eu_private_ip_address_hub" {
  description = "The private IP address of Hub VM in Germany:"
  value       = azurerm_network_interface.eu_transit_subnet_nic_1.private_ip_address
}
output "eu_public_ip_address_hub" {
  description = "The public IP address of Hub VM in Germany:"
  value       = data.azurerm_public_ip.eu_hub_pip.ip_address
}
output "eu_private_ip_address_spoke1" {
  description = "The private IP address of Hub VM in France Central:"
  value       = azurerm_network_interface.eu_spoke1_subnet_nic_1.private_ip_address
}
output "eu_public_ip_address_spoke1" {
  description = "The public IP address of Spoke1 VM in France Central:"
  value       = data.azurerm_public_ip.eu_spoke1_pip.ip_address
}
output "eu_private_ip_address_spoke2" {
  description = "The private IP address of Hub VM in UK South:"
  value       = azurerm_network_interface.eu_spoke2_subnet_nic_1.private_ip_address
}
output "eu_public_ip_address_spoke2" {
  description = "The public IP address of Spoke2 VM in UK South:"
  value       = data.azurerm_public_ip.eu_spoke2_pip.ip_address
}
