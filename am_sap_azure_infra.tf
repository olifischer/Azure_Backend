# --------------------------------------------------------------------------
# Create Ressource Group
# --------------------------------------------------------------------------

resource "azurerm_resource_group" "rg_am" {
  name     = "osf_rg_sap_am"
  location = "West US"

  tags = {
    name = "osf_sap"
  }
}

# --------------------------------------------------------------------------
# Create Europe NSG which is shared across all vNets in Europe
# This Rule will allow SSH, HTTP and HTTPS
# --------------------------------------------------------------------------

resource "azurerm_network_security_group" "am_nsg" {
  name                = "am-nsg"
  location            = azurerm_resource_group.rg_am.location
  resource_group_name = azurerm_resource_group.rg_am.name

  tags = {
    name = "osf_sap"
  }
}
resource "azurerm_network_security_rule" "am_nsg_rule" {
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
  resource_group_name         = azurerm_resource_group.rg_am.name
  network_security_group_name = azurerm_network_security_group.am_nsg.name
}

# --------------------------------------------------------------------------
#           ******** Create eu_transit_vnet environment ********
# --------------------------------------------------------------------------

# ---------- Create eu_transit_vnet (HUB) ----------
resource "azurerm_virtual_network" "am_transit_vnet" {
  name                = "am-transit-vnet"
  resource_group_name = azurerm_resource_group.rg_am.name
  location            = azurerm_resource_group.rg_am.location
  address_space       = ["10.1.2.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_transit_subnet (HUB) ----------
resource "azurerm_subnet" "am_transit_subnet1" {
  name                 = "am-transit-subnet1"
  resource_group_name  = azurerm_resource_group.rg_am.name
  virtual_network_name = azurerm_virtual_network.am_transit_vnet.name
  address_prefixes     = ["10.1.2.0/24"]
}
# ---------- Create network interface nic (HUB) ----------
resource "azurerm_network_interface" "am_transit_subnet_nic_1" {
  name                 = "am-transit-subnet-nic-1"
  location             = azurerm_resource_group.rg_am.location
  resource_group_name  = azurerm_resource_group.rg_am.name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.am_transit_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.am_hub_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (HUB) ----------
resource "azurerm_virtual_machine" "am_hub_vm" {
  name                          = "am-hub-vm"
  resource_group_name           = azurerm_resource_group.rg_am.name
  location                      = azurerm_resource_group.rg_am.location
  primary_network_interface_id  = azurerm_network_interface.am_transit_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.am_transit_subnet_nic_1.id]
  vm_size                       = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "am-hub-vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "am-hub-vm-1"
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
resource "azurerm_route_table" "am_user_defined_route_table_hub" {
  name                          = "am-user-defined-route-table_hub"
  location                      = azurerm_resource_group.rg_am.location
  resource_group_name           = azurerm_resource_group.rg_am.name
  disable_bgp_route_propagation = false

  # route {
  #   name           = "udr_hub_to_spoke1"
  #   address_prefix = "10.1.3.0/24"
  #   next_hop_type  = "vnetlocal"
  #   #next_hop_in_ip_address = "vnetlocal"
  # }

  tags = {
    name = "osf_sap"
  }
}
# ---------- Associate eu_hub route table (HUB) ----------
resource "azurerm_subnet_route_table_association" "am_rt_hub" {
  subnet_id      = azurerm_subnet.am_transit_subnet1.id
  route_table_id = azurerm_route_table.am_user_defined_route_table_hub.id
}
# --------------------------------------------------------------------------
# Application_1 network configuration
# --------------------------------------------------------------------------

# ---------- Create eu_app_1 virtual network (SPOKE1) ----------
resource "azurerm_virtual_network" "am_app_1" {
  name                = "am-app-1"
  resource_group_name = azurerm_resource_group.rg_am.name
  location            = "West US 2"
  address_space       = ["10.1.3.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_1 subnet (SPOKE1) ----------
resource "azurerm_subnet" "am_app1_subnet1" {
  name                 = "am-app1-subnet1"
  resource_group_name  = azurerm_resource_group.rg_am.name
  virtual_network_name = azurerm_virtual_network.am_app_1.name
  address_prefixes     = ["10.1.3.0/24"]
}
# ---------- Create network interface nic (SPOKE1) ----------
resource "azurerm_network_interface" "am_spoke1_subnet_nic_1" {
  name                 = "am-spoke1-subnet-nic-1"
  resource_group_name  = azurerm_resource_group.rg_am.name
  location             = "West US 2"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.am_app1_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.am_spoke1_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (SPOKE1) ----------
resource "azurerm_virtual_machine" "am_spoke1_vm" {
  name                          = "am-spoke1-vm"
  resource_group_name           = azurerm_resource_group.rg_am.name
  location                      = "West US 2"
  primary_network_interface_id  = azurerm_network_interface.am_spoke1_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.am_spoke1_subnet_nic_1.id]
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
resource "azurerm_route_table" "am_user_defined_route_table_spoke1" {
  name                          = "am-user-defined-route-table-spoke1"
  location                      = "West US 2"
  resource_group_name           = azurerm_resource_group.rg_am.name
  disable_bgp_route_propagation = false

# ---------- Spoke should forward all traffic with 10 to NVA ----------
  route {
    name                   = "to_spoke2"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.am_transit_subnet_nic_1.private_ip_address
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Associate eu_app_1 route table (SPOKE1) ----------
resource "azurerm_subnet_route_table_association" "am_rt_spoke1" {
  subnet_id      = azurerm_subnet.am_app1_subnet1.id
  route_table_id = azurerm_route_table.am_user_defined_route_table_spoke1.id
}

# --------------------------------------------------------------------------
# Application_2 network configuration
# --------------------------------------------------------------------------

# ---------- Create eu_app_2 virtual network (SPOKE2) ----------
resource "azurerm_virtual_network" "am_app_2" {
  name                = "am-app-2"
  resource_group_name = azurerm_resource_group.rg_am.name
  location            = "West Central US"
  address_space       = ["10.1.4.0/24"]

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_2 subnet (SPOKE2) ----------
resource "azurerm_subnet" "am_app2_subnet1" {
  name                 = "am-app2-subnet1"
  resource_group_name  = azurerm_resource_group.rg_am.name
  virtual_network_name = azurerm_virtual_network.am_app_2.name
  address_prefixes     = ["10.1.4.0/24"]
}
# ---------- Create network interface nic (SPOKE2) ----------
resource "azurerm_network_interface" "am_spoke2_subnet_nic_1" {
  name                 = "am-spoke2-subnet-nic-1"
  resource_group_name  = azurerm_resource_group.rg_am.name
  location             = "West Central US"
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.am_app2_subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.am_spoke2_pip.id
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create virtual machine vm (SPOKE2) ----------
resource "azurerm_virtual_machine" "am_spoke2_vm" {
  name                          = "am-spoke2-vm"
  resource_group_name           = azurerm_resource_group.rg_am.name
  location                      = "West Central US"
  primary_network_interface_id  = azurerm_network_interface.am_spoke2_subnet_nic_1.id
  network_interface_ids         = [azurerm_network_interface.am_spoke2_subnet_nic_1.id]
  vm_size                       = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "am-spoke2-vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "am-spoke2-vm-1"
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
resource "azurerm_route_table" "am_user_defined_route_table_spoke2" {
  name                          = "am-user-defined-route-table-spoke2"
  location                      = "West Central US"
  resource_group_name           = azurerm_resource_group.rg_am.name
  disable_bgp_route_propagation = false

# ---------- Spoke should forward all traffic with 10 to NVA ----------
  route {
    name                   = "to_spoke1"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.am_transit_subnet_nic_1.private_ip_address
  }
  tags = {
    name = "osf_sap"
  }
}
# ---------- Create eu_app_1 route table (SPOKE2) ----------
resource "azurerm_subnet_route_table_association" "am_rt_spoke2" {
  subnet_id      = azurerm_subnet.am_app2_subnet1.id
  route_table_id = azurerm_route_table.am_user_defined_route_table_spoke2.id
}

# --------------------------------------------------------------------------
# Create Global vNet peering for EU transit_vnet and application layer
# --------------------------------------------------------------------------

# ---------- Create vnet peering between Hub and SPOKE1 ----------
resource "azurerm_virtual_network_peering" "am_hub_2_eu_app_1" {
  name                         = "am-hub-2-eu-app-1"
  resource_group_name          = azurerm_resource_group.rg_am.name
  virtual_network_name         = azurerm_virtual_network.am_transit_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.am_app_1.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}
# ---------- Create vnet peering between SPOKE1 and HUB ----------
resource "azurerm_virtual_network_peering" "am_app_1_2_eu_hub" {
  name                         = "am-app-1-2-eu-hub"
  resource_group_name          = azurerm_resource_group.rg_am.name
  virtual_network_name         = azurerm_virtual_network.am_app_1.name
  remote_virtual_network_id    = azurerm_virtual_network.am_transit_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
# ---------- Create vnet peering between Hub and SPOKE2 ----------
resource "azurerm_virtual_network_peering" "am_hub_2_am_app_2" {
  name                         = "am-hub-2-am-app-2"
  resource_group_name          = azurerm_resource_group.rg_am.name
  virtual_network_name         = azurerm_virtual_network.am_transit_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.am_app_2.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}
# ---------- Create vnet peering between SPOKE2 and Hub ----------
resource "azurerm_virtual_network_peering" "am_app_2_2_am_hub" {
  name                         = "am-app-2-2-am-hub"
  resource_group_name          = azurerm_resource_group.rg_am.name
  virtual_network_name         = azurerm_virtual_network.am_app_2.name
  remote_virtual_network_id    = azurerm_virtual_network.am_transit_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# --------------------------------------------------------------------------
# Create Public IP (pip) for host in eu_transit_subnet1
# --------------------------------------------------------------------------

# ---------- Create Public Inetner IP for Hub VM ----------
resource "azurerm_public_ip" "am_hub_pip" {
  name                = "am-hub-pip"
  location            = azurerm_resource_group.rg_am.location
  resource_group_name = azurerm_resource_group.rg_am.name
  allocation_method   = "Dynamic"

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Public Inetner IP for Spoke1 VM ----------
resource "azurerm_public_ip" "am_spoke1_pip" {
  name                = "am-spoke1-pip"
  location            = "West US 2"
  resource_group_name = azurerm_resource_group.rg_am.name
  allocation_method   = "Dynamic"

  tags = {
    name = "osf_sap"
  }
}
# ---------- Create Public Inetner IP for Spoke2 VM ----------
resource "azurerm_public_ip" "am_spoke2_pip" {
  name                = "am-spoke2-pip"
  location            = "West Central US"
  resource_group_name = azurerm_resource_group.rg_am.name
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
data "azurerm_public_ip" "am_hub_pip" {
  name = "am-hub-pip"
  resource_group_name = azurerm_resource_group.rg_am.name
  depends_on = [azurerm_virtual_machine.am_hub_vm]
}
data "azurerm_public_ip" "am_spoke1_pip" {
  name = "am-spoke1-pip"
  resource_group_name = azurerm_resource_group.rg_am.name
  depends_on = [azurerm_virtual_machine.am_spoke1_vm]
}
data "azurerm_public_ip" "am_spoke2_pip" {
  name = "am-spoke2-pip"
  resource_group_name = azurerm_resource_group.rg_am.name
  depends_on = [azurerm_virtual_machine.am_spoke2_vm]
}

output "am_private_ip_address_hub" {
  description = "The private IP address of Hub VM in West US:"
  value       = azurerm_network_interface.am_transit_subnet_nic_1.private_ip_address
}
output "am_public_ip_address_hub" {
  description = "The public IP address of Hub VM in West US:"
  value       = data.azurerm_public_ip.am_hub_pip.ip_address
}
output "am_private_ip_address_spoke1" {
  description = "The private IP address of Hub VM in West US 2:"
  value       = azurerm_network_interface.am_spoke1_subnet_nic_1.private_ip_address
}
output "am_public_ip_address_spoke1" {
  description = "The public IP address of Spoke1 VM in West US 2:"
  value       = data.azurerm_public_ip.am_spoke1_pip.ip_address
}
output "am_private_ip_address_spoke2" {
  description = "The private IP address of Hub VM in West Central US:"
  value       = azurerm_network_interface.am_spoke2_subnet_nic_1.private_ip_address
}
output "am_public_ip_address_spoke2" {
  description = "The public IP address of Spoke2 VM in West Central US:"
  value       = data.azurerm_public_ip.am_spoke2_pip.ip_address
}
