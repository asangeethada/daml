resource "secret_resource" "vsts-token" {}
resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

resource "azurerm_virtual_network" "my_terraform_network" {
  name                = "myVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "my_terraform_subnet" {
  name                 = "mySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_terraform_network.name
  address_prefixes     = ["10.0.1.0/24"]
}


resource "azurerm_public_ip_prefix" "pubip_prefix" {
    name                = "ip-prefix-vmss"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    prefix_length = 31
}

resource "azurerm_network_security_group" "my_terraform_nsg" {
  name                = "myNetworkSecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = ["35.198.147.95/32", "35.194.81.56/32"]  # Frankfurt and NV 
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Deny_subnet_traffic"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = azurerm_subnet.my_terraform_subnet.address_prefixes[0]
    destination_address_prefix = azurerm_subnet.my_terraform_subnet.address_prefixes[0]
  }

}

# Create (and display) an SSH key
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine_scale_set" "deployment" {
  name                = "buildagent-vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard_DS1_v2" #Standard_F16s_v2 to match current setup on GCP
  instances           = 1 //var.numberOfWorkerNodes # number of instances

  overprovision          = false
  single_placement_group = false

  admin_username      = "adminuser"

  disable_password_authentication = true

  custom_data = base64encode(templatefile("startup.sh" , {
    vsts_token=  secret_resource.vsts-token.value     
    vsts_account = "digitalasset"
    vsts_pool    = "test-ubuntu-pool"
    size         = 400
    }))

 admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.example_ssh.public_key_openssh
  }



  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadOnly"

    diff_disk_settings {
      option = "Local"
    }
  }
  data_disk {
    storage_account_type = "StandardSSD_LRS"
    create_option       = "Empty"
    caching              = "ReadWrite"
    lun                  = 0
    disk_size_gb         = 400
  }

    network_interface {
        name    = "external"
        primary = true
        dns_servers = []

        ip_configuration {
            application_gateway_backend_address_pool_ids  = []
            application_security_group_ids                = []
            load_balancer_backend_address_pool_ids        = []
            load_balancer_inbound_nat_rules_ids           = []
            name      = "external"
            primary   = true
            subnet_id = azurerm_subnet.my_terraform_subnet.id

            public_ip_address {
                name                = "public-ip-address"
                public_ip_prefix_id = azurerm_public_ip_prefix.pubip_prefix.id
            }

        }
      

        network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
      }

  boot_diagnostics {
    storage_account_uri = null
  }

    identity {
    type = "SystemAssigned"
  }
  extension { 
  name                       = "AADSSHLoginForLinux"
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  //virtual_machine_id         = azurerm_linux_virtual_machine.my_terraform_vm.id
  }
lifecycle {
  ignore_changes = [
    extension, 
    tags, 
    instances,
  ]
}
}

resource "azurerm_monitor_autoscale_setting" "example" {
  name                = "myAutoscaleSetting"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.deployment.id

  profile {
    name = "Maintain-Scale"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }
}
}


# Data template Bash bootstrapping file
data "local_file" "startup" {
    filename = "${path.module}/startup.sh"
}

# Config for periodic Killer
data "azurerm_subscription" "current" {}


# Create network interface
resource "azurerm_network_interface" "my_vm_nic" {
  name                = "myNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "periodic_killer_nic"
    subnet_id                     = azurerm_subnet.my_terraform_subnet.id
    private_ip_address_allocation = "Dynamic"
    //public_ip_address_id          = azurerm_public_ip.my_vm_public_ip.id
  }
}



resource "azurerm_linux_virtual_machine" "my_terraform_vm" {
  name                  = "myVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_vm_nic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

   custom_data = filebase64("startup-killer.sh")

  computer_name                   = "myvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
  //custom_data = filebase64("startup.sh")
  identity {
    type = "SystemAssigned"
  }
}

//Can be set to any Azure role
data "azurerm_role_definition" "contributor" { 
  name = "Contributor"
}

resource "azurerm_role_assignment" "example" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = "${data.azurerm_subscription.current.id}${data.azurerm_role_definition.contributor.id}"
  principal_id       = azurerm_linux_virtual_machine.my_terraform_vm.identity[0].principal_id
}