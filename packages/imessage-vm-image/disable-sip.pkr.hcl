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

# Adapted from cirruslabs/macos-image-templates (templates/disable-sip.pkr.hcl).
# Works on the existing VM in place: boots it into recovery and types the
# commands over VNC, since there is nothing to SSH into there.
source "tart-cli" "tart" {
  vm_name      = "${var.vm_name}"
  recovery     = true
  communicator = "none"
  boot_command = [
    # Skip over "Macintosh" and select "Options" to boot into macOS Recovery
    "<wait60s><right><right><enter>",
    # Open Terminal
    "<wait10s><leftAltOn>T<leftAltOff>",
    # Disable SIP; it asks for confirmation, then the admin password
    "<wait10s>csrutil disable<enter>",
    "<wait10s>y<enter>",
    "<wait10s>admin<enter>",
    "<wait10s>halt<enter>"
  ]
}

build {
  sources = ["source.tart-cli.tart"]
}
