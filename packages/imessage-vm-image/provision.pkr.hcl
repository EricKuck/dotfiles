packer {
  required_plugins {
    tart = {
      version = "= 1.21.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_name" {
  type = string
}

variable "authorized_keys" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

# /etc/kcpassword contents for auto-login, hex encoded by the wrapper script.
variable "kcpassword_hex" {
  type      = string
  sensitive = true
}

# Boots the SIP-disabled VM and replaces the vanilla image's admin/admin
# account with eric. The build runs on Tart's NAT network, so the default
# password is never reachable from the LAN.
source "tart-cli" "tart" {
  vm_name      = "${var.vm_name}"
  headless     = true
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "180s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    environment_vars = [
      "PASSWORD=${var.password}",
      "KCPASSWORD_HEX=${var.kcpassword_hex}",
    ]
    inline = [
      # Fail the build instead of handing back a VM the Private API can't use.
      "csrutil status | grep -q 'disabled' || { csrutil status; exit 1; }",

      "sudo sysadminctl -addUser eric -fullName 'Eric Kuck' -password \"$PASSWORD\" -admin -adminUser admin -adminPassword admin",
      "sudo createhomedir -c -u eric",
      "echo 'eric ALL=(ALL) NOPASSWD: ALL' | sudo EDITOR=tee visudo /etc/sudoers.d/eric-nopasswd",

      "sudo -u eric mkdir -p -m 700 ~eric/.ssh",
      "echo '${var.authorized_keys}' | sudo -u eric tee ~eric/.ssh/authorized_keys > /dev/null",
      "sudo chmod 600 ~eric/.ssh/authorized_keys",

      "echo \"$KCPASSWORD_HEX\" | xxd -r -p | sudo tee /etc/kcpassword > /dev/null",
      "sudo chmod 600 /etc/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser eric",
    ]
  }
}
