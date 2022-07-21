output "ip_addresses" {
  value = azurerm_network_interface.worker.*.private_ip_address
}
