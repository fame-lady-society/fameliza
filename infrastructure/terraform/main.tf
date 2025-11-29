terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "linode" {
  token = var.linode_token
}

resource "linode_instance" "fameliza" {
  label           = var.instance_label
  image           = "linode/ubuntu22.04"
  region          = var.region
  type            = var.instance_type
  authorized_keys = [var.ssh_public_key]
  root_pass       = var.root_password

  stackscript_id = linode_stackscript.setup.id
  stackscript_data = {
    "git_repo"     = var.git_repo
    "git_branch"   = var.git_branch
    "domain"       = var.domain
  }

  tags = [var.instance_label]

  lifecycle {
    create_before_destroy = true
  }
}

resource "linode_firewall" "fameliza" {
  label = "${var.instance_label}-firewall"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound_policy = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [linode_instance.fameliza.id]
}

resource "linode_stackscript" "setup" {
  label       = "${var.instance_label}-setup"
  description = "Initial server setup for Fameliza"
  script      = file("${path.module}/../scripts/setup-server.sh")
  images      = ["linode/ubuntu22.04"]
  is_public   = false
}

