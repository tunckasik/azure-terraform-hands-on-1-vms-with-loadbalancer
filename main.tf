terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.41.0"
    }
  }
}

provider "azurerm" {
  # Configuration options
  features {

  }
}

# Create a resource group
resource "azurerm_resource_group" "rg1" {
  name     = var.rg_name
  location = var.location
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.rg1.name
  location            = var.location
  address_space       = ["10.60.0.0/22"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = var.subnet1_name
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.0.0/24"]
}

resource "azurerm_subnet" "subnet2" {
  name                 = var.subnet2_name
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.1.0/24"]
}


module "vm1" {
  source = "./module/vm"
  vm_name = "vm1"
  rg_name = azurerm_resource_group.rg1.name
  vm_username = "bronze"
  vm_password = "4321Boom!"
  subnet_id = azurerm_subnet.subnet1.id
}

module "vm2" {
  source = "./module/vm"
  vm_name = "vm2"
  rg_name = azurerm_resource_group.rg1.name
  vm_username = "bronze"
  vm_password = "4321Boom!"
  subnet_id = azurerm_subnet.subnet2.id
}

resource "azurerm_network_security_group" "nsg" {
  name                = "acceptanceTestSecurityGroup1"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg1.name

  security_rule {
    name                       = "nsg-sc-rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
  resource "azurerm_subnet_network_security_group_association" "nsg_subnet_1" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
  resource "azurerm_subnet_network_security_group_association" "nsg_subnet_2" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_resource_group" "rg2" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_public_ip" "pip" {
  name                = "acceptanceTestPublicIp1"
  resource_group_name = azurerm_resource_group.rg2.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" #Default is Basic and cannot work

  tags = {
    environment = "Production"
  }
}
resource "azurerm_lb" "lb" {
  name                = "TestLoadBalancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg2.name
  sku                 = "Standard" #Default is Basic and cannot work

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "backendlb" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "probelb" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "http-running-probe"
  port            = 80
}

resource "azurerm_lb_rule" "rulelb" {
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.probelb.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend_address_pool_id]
}

resource "azurerm_network_interface_backend_address_pool_association" "backend_assoc1" {
  network_interface_id    = module.vm1.nic_id
  ip_configuration_name   = "testconfiguration1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backendlb.id
}

resource "azurerm_network_interface_backend_address_pool_association" "backend_assoc2" {
  network_interface_id    = module.vm2.nic_id
  ip_configuration_name   = "testconfiguration1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backendlb.id
}
resource "azurerm_virtual_machine_extension" "vm-extensions" {
    name                  = "vm01-ext-webserver"
    virtual_machine_id    = module.vm.vm_id
    publisher             = "Microsoft.Compute"
    type                  = "CustomScriptExtension"
    type_handler_version = "1.10"
    settings = <<SETTINGS
        {
        "commandToExecute": "powershell Add-WindowsFeature Web-Server"
        }
        SETTINGS
}

