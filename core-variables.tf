#############################
## Application - Variables ##
#############################

# company name 
variable "company" {
  type = string
  description = "The company name used to build resources"
}
# application name 
variable "app_name" {
  type        = string
  description = "This variable defines the application name used to build resources"
}
# Storage Account 
variable "StorageAccount" {
  type = string
  description = "The StorageAccount name used to build resource"
}
# KeyVault
variable "KeyVault" {
  type = string
  description = "The environment to be built"
}
# azure region
variable "location" {
  type = string
  description = "Azure region where resources will be created"
}
## Network - Variables ##
variable "VNET" {
  type = string
  description = "The CIDR of the network VNET"
}
#Frontend Subnet
variable "FrontendSubnet" {
  type = string
  description = "The CIDR for the Frontend subnet"
}
#Backend Subnet
variable "BackendSubnet" {
  type = string
  description = "The CIDR for the Backend subnet"
}
#Private Endpoint Subnet
variable "PESubnet" {
  type = string
  description = "The CIDR for the Private Endpoint subnet"
}
#Log Analytics Workspace
variable "logAnalytics" {
  type = string
  description = "The name for Log Analytics workspace"
}
#Azure Backup
variable "Backup" {
  type = string
  description = "The name to create for Azure Backup"
}
