variable "ip_address" {
  type = string
}

variable "ssh_path" {
  type = string
}

variable "vm_name" {
  type = string
}


terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "rg-dev-machine" {
  name     = "rg-dev-machine"
  location = "UKSouth"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "vn-dev-machine" {
  name                = "vnet-dev-machine"
  resource_group_name = azurerm_resource_group.rg-dev-machine.name
  location            = azurerm_resource_group.rg-dev-machine.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}


resource "azurerm_subnet" "sn-dev-machine" {
  name                 = "snet-dev-machine"
  resource_group_name  = azurerm_resource_group.rg-dev-machine.name
  virtual_network_name = azurerm_virtual_network.vn-dev-machine.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "nsg-dev-machine" {
  name                = "nsg-dev-machine"
  resource_group_name = azurerm_resource_group.rg-dev-machine.name
  location            = azurerm_resource_group.rg-dev-machine.location

  tags = {
    environment = "dev"
  }

  security_rule {
    name                       = "nsgsr-dev-machine"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.ip_address
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "sga-dev-machine" {
  subnet_id                 = azurerm_subnet.sn-dev-machine.id
  network_security_group_id = azurerm_network_security_group.nsg-dev-machine.id
}

resource "azurerm_public_ip" "pip-dev-machine" {
  name                = "pip-dev-machine"
  resource_group_name = azurerm_resource_group.rg-dev-machine.name
  location            = azurerm_resource_group.rg-dev-machine.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}


resource "azurerm_network_interface" "nic-dev-machine" {
  name                = "nic-dev-machine"
  location            = azurerm_resource_group.rg-dev-machine.location
  resource_group_name = azurerm_resource_group.rg-dev-machine.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sn-dev-machine.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-dev-machine.id
  }

  tags = {
    environment = "dev"
  }
}


resource "azurerm_linux_virtual_machine" "vm-DevWork" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.rg-dev-machine.name
  location            = azurerm_resource_group.rg-dev-machine.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.nic-dev-machine.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file(join("", [var.ssh_path, ".pub"]))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("windows-ssh-script.tpl", {
      hostname     = self.public_ip_address
      user         = "adminuser"
      identityfile = var.ssh_path
    })
    interpreter = ["Powershell", "-Command"]
  }
}
