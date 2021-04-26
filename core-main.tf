# Create a Resource Group
resource "azurerm_resource_group" "terraform-rg" {
  name     = "kopi-${var.location}-${var.app_name}-rg"
  location = var.location
}

## Create Vnet ##
resource "azurerm_virtual_network" "Vnet"{
    name                = var.VNET
    address_space       = ["10.16.0.0/16"]
    location            = azurerm_resource_group.terraform-rg.location
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Create Frontend Subnet ##
resource "azurerm_subnet" "Frontendsubnet"{
    name                = var.FrontendSubnet
    address_prefixes    = ["10.16.1.0/24"]
    virtual_network_name = azurerm_virtual_network.Vnet.name
    resource_group_name = azurerm_resource_group.terraform-rg.name

   # enforce_private_link_service_network_policies = true
}

## Create Backend Subnet ##
resource "azurerm_subnet" "Backendsubnet"{
    name                = var.BackendSubnet
    address_prefixes    = ["10.16.2.0/24"]
    virtual_network_name = azurerm_virtual_network.Vnet.name
    resource_group_name = azurerm_resource_group.terraform-rg.name

    #enforce_private_link_service_network_policies = true
}

## Create Private Endpoint Subnet ##
resource "azurerm_subnet" "PEsubnet"{
    name                = var.PESubnet
    address_prefixes    = ["10.16.3.0/24"]
    virtual_network_name = azurerm_virtual_network.Vnet.name
    resource_group_name = azurerm_resource_group.terraform-rg.name

    enforce_private_link_service_network_policies = true
    enforce_private_link_endpoint_network_policies = true
}

## Create Azure Site Recovery for Backup ##
resource "azurerm_recovery_services_vault" "rsv" {
    name = var.Backup
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    sku = "Standard"
    identity {
        type = "SystemAssigned"
        
    }
}
## Get Subscription detail ##
data "azurerm_subscription" "current" {}

##Get Role detail for Contributor role ##
data "azurerm_role_definition" "contributor" {
  name = "Contributor"
}

## Create role assignment for ASR ##
resource "azurerm_role_assignment" "acl" {
    depends_on = [azurerm_recovery_services_vault.rsv]
##Not Required##  name               = azurerm_recovery_services_vault.rsv.name
    scope              = data.azurerm_subscription.current.id
    role_definition_id = "${data.azurerm_subscription.current.id}${data.azurerm_role_definition.contributor.id}"
    principal_id       = azurerm_recovery_services_vault.rsv.identity[0].principal_id
}

## Create Private Endpoint for ASR Backup ##
resource "azurerm_private_endpoint" "endpoint_backup" {
    depends_on = [azurerm_role_assignment.acl]
    name = "privateendpointfor${azurerm_recovery_services_vault.rsv.name}"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    subnet_id           = azurerm_subnet.PEsubnet.id

    private_service_connection {
        name                           = "serviceconnectionfor${azurerm_recovery_services_vault.rsv.name}"
        private_connection_resource_id = azurerm_recovery_services_vault.rsv.id
        is_manual_connection           = false
        subresource_names = [ "AzureBackup" ]
    }
}

## Create Private DNS zone for ASR Backup ##
resource "azurerm_private_dns_zone" "dnszoneforkopiasr01" {
    name    = "privatelink.ne.backup.windowsazure.com"
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Link Vnet to DNS zone for ASR Backup ##
resource "azurerm_private_dns_zone_virtual_network_link" "pl_pe_asr" {
    name = "privatelink-vnet-asr"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    private_dns_zone_name = azurerm_private_dns_zone.dnszoneforkopiasr01.name
    virtual_network_id = azurerm_virtual_network.Vnet.id
    registration_enabled = true
}

## Create Backup policy for VM ##
resource "azurerm_backup_policy_vm" "backup_policy" {
  name                = "Backup-policy"
  resource_group_name = azurerm_resource_group.terraform-rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv.name

  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 10
  }

  retention_weekly {
    count    = 42
    weekdays = ["Sunday", "Wednesday", "Friday", "Saturday"]
  }

  retention_monthly {
    count    = 7
    weekdays = ["Sunday", "Wednesday"]
    weeks    = ["First", "Last"]
  }

  retention_yearly {
    count    = 77
    weekdays = ["Sunday"]
    weeks    = ["Last"]
    months   = ["January"]
  }
}

## Create Azure KeyVault ##
data "azurerm_client_config" "current" {}
resource "azurerm_key_vault" "keyvault" {
    name = var.KeyVault
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    network_acls{
        bypass = "AzureServices"
        default_action = "Deny"
        ip_rules = [ "0.0.0.0/0" ]
        virtual_network_subnet_ids = []
    }
    sku_name = "standard"
    tenant_id = data.azurerm_client_config.current.tenant_id
    access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    key_permissions = [
      "get",
    ]
    secret_permissions = [
      "get", "backup", "delete", "list", "purge", "recover", "restore", "set",
    ]
    storage_permissions = [
      "get",
    ]
  }
}

## Create Private DNS Zone ##
resource "azurerm_private_dns_zone" "privatelinkdnszone" {
    name    = "privatelink.vaultcore.azure.net"
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Create Private Endpoint service for KeyVault, Storage Account and Backup ##
resource "azurerm_private_endpoint" "privateendpoint_keyvault" {
    name                = "privateendpointfor${var.KeyVault}"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    subnet_id           = azurerm_subnet.PEsubnet.id

    private_service_connection {
        name                           = "privateserviceconnectionfor${var.KeyVault}"
        private_connection_resource_id = azurerm_key_vault.keyvault.id
        is_manual_connection           = false
        subresource_names = [ "Vault" ]
    }

   # private_dns_zone_group {
   #     name = azurerm.private_dns_zone.privatelinkdnszone.name
   #     private_dns_zone_ids = [ azurerm.private_dns_zone.privatelinkdnszone.id ]
   # }
}

## Link Vnet to DNS zone ##
resource "azurerm_private_dns_zone_virtual_network_link" "pl_pe_vault" {
    name = "privatelink-vnet-vault"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    private_dns_zone_name = azurerm_private_dns_zone.privatelinkdnszone.name
    virtual_network_id = azurerm_virtual_network.Vnet.id
    registration_enabled = false
}

## Keyvault Private Endpoint Connection ##
data "azurerm_private_endpoint_connection" "endpoint_connection" {
    depends_on = [azurerm_private_endpoint.privateendpoint_keyvault]
    name = azurerm_private_endpoint.privateendpoint_keyvault.name
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Add A Record in Private DNS Zone ##
resource "azurerm_private_dns_a_record" "dnsarecordforkey" {
    depends_on = [azurerm_key_vault.keyvault]
    name = azurerm_key_vault.keyvault.name
    zone_name = azurerm_private_dns_zone.privatelinkdnszone.name
    resource_group_name = azurerm_resource_group.terraform-rg.name
    ttl = 300
    records = [data.azurerm_private_endpoint_connection.endpoint_connection.private_service_connection.0.private_ip_address]
}

## Create Storage Account ##
resource "azurerm_storage_account" "storageaccount" {
    name                        = var.StorageAccount
    resource_group_name         = azurerm_resource_group.terraform-rg.name
    location                    = azurerm_resource_group.terraform-rg.location
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

## Create Private Endpoint service for Storage Account ##
resource "azurerm_private_endpoint" "privateendpoint_storageaccount" {
    name                = "privateendpointfor${var.StorageAccount}"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    subnet_id           = azurerm_subnet.PEsubnet.id

    private_service_connection {
        name                           = "privateserviceconnectionfor${var.StorageAccount}"
        private_connection_resource_id = azurerm_storage_account.storageaccount.id
        is_manual_connection           = false
        subresource_names = [ "blob" ]
    }
}

## Create Private DNS Zone for Storage Account ##
resource "azurerm_private_dns_zone" "dnszone_storageaccount" {
    name    = "privatelink.blob.core.windows.net"
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Link Vnet to DNS zone for Blob storage account ##
resource "azurerm_private_dns_zone_virtual_network_link" "vnetlink_dns_blob" {
    name = "privatelink-vnet-blob"
    resource_group_name = azurerm_resource_group.terraform-rg.name
    private_dns_zone_name = azurerm_private_dns_zone.dnszone_storageaccount.name
    virtual_network_id = azurerm_virtual_network.Vnet.id
    registration_enabled = false
}

## Blob Storage account Private Endpoint Connection ##
data "azurerm_private_endpoint_connection" "endpoint_connection_blob" {
    depends_on = [azurerm_private_endpoint.privateendpoint_storageaccount]
    name = azurerm_private_endpoint.privateendpoint_storageaccount.name
    resource_group_name = azurerm_resource_group.terraform-rg.name
}

## Add A Record in Private DNS Zone ##
resource "azurerm_private_dns_a_record" "dnsarecord_blob" {
    depends_on = [azurerm_storage_account.storageaccount]
    name = azurerm_storage_account.storageaccount.name
    zone_name = azurerm_private_dns_zone.dnszone_storageaccount.name
    resource_group_name = azurerm_resource_group.terraform-rg.name
    ttl = 300
    records = [data.azurerm_private_endpoint_connection.endpoint_connection.private_service_connection.0.private_ip_address]
}

## Create Log Analytics Workspace ##
resource "azurerm_log_analytics_workspace" "law" {
    name                = var.logAnalytics
    resource_group_name = azurerm_resource_group.terraform-rg.name
    location            = azurerm_resource_group.terraform-rg.location
    sku                 = "Free"
}
