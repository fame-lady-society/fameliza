output "instance_ip" {
  description = "Public IP address of the Linode instance"
  value       = linode_instance.fameliza.ipv4
}

output "instance_id" {
  description = "ID of the Linode instance"
  value       = linode_instance.fameliza.id
}

output "firewall_id" {
  description = "ID of the firewall"
  value       = linode_firewall.fameliza.id
}

