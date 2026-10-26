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

# Throwaway key the wrapper script generated and provision.pkr.hcl authorized.
# Not the password: the plugin's shutdown command interpolates that into a
# shell command unquoted.
variable "ssh_key" {
  type = string
}

# Where the guest's sops public key is downloaded to.
variable "output_dir" {
  type = string
}

# Logs in as eric (admin can't delete itself while logged in), removes the
# vanilla admin account, installs Nix and locks SSH down to the real keys.
source "tart-cli" "tart" {
  vm_name              = "${var.vm_name}"
  headless             = true
  ssh_username         = "eric"
  ssh_private_key_file = "${var.ssh_key}"
  ssh_timeout          = "180s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      "sudo sysadminctl -deleteUser admin",
      "sudo rm -f /etc/sudoers.d/admin-nopasswd",

      # Same upstream installer the other Macs use; nix-darwin takes it over.
      "curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon --yes",
      # The first deploy copies the system closure in as eric, before
      # nix-darwin manages this setting.
      "echo 'trusted-users = root eric' | sudo tee -a /etc/nix/nix.conf",

      # Same layout as the other hosts: sops-nix decrypts with this key.
      "ssh-keygen -q -t ed25519 -N '' -C eric@imessage-bridge-sops -f ~/.ssh/id_ed25519_sops",

      # IRLBuild forwards SSH from the LAN, so only keys get in.
      "printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\n' | sudo tee /etc/ssh/sshd_config.d/050-imessage-vm.conf",
    ]
  }

  provisioner "file" {
    direction   = "download"
    source      = "/Users/eric/.ssh/id_ed25519_sops.pub"
    destination = "${var.output_dir}/"
  }

  # Last: Packer's connection stays open for the shutdown, but new logins
  # can't use the build key anymore.
  provisioner "shell" {
    inline = ["sed -i '' '/ imessage-vm-build$/d' ~/.ssh/authorized_keys"]
  }
}
