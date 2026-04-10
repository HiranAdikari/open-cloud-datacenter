# ── VyOS bootstrap module ─────────────────────────────────────────────────────
#
# Deploys the VyOS gateway VM on Harvester. Designed for a two-apply workflow:
#
#   Apply 1 (iso_installed = false):
#     - Creates image, trunk network, and VM with ISO CDROM (boot_order=1)
#     - Operator opens Harvester console → logs in → runs 'install image'
#     - Operator reboots the VM
#
#   Apply 2 (iso_installed = true):
#     - Removes the CDROM disk; rootdisk becomes the sole boot device
#     - VM restarts from installed disk
#
#   After Apply 2: use the vyos-tenant module (REST API) for configuration.
#
# VyOS does not ship qemu-guest-agent — the VM IP will not appear in Harvester
# UI. Use the known static IP configured post-install on eth0.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  trunk_network_namespace = coalesce(var.trunk_network_namespace, var.vm_namespace)
  trunk_network_name      = "${var.vm_name}-eth1-trunk"
}

# ── VyOS ISO image ────────────────────────────────────────────────────────────

resource "harvester_image" "vyos" {
  name         = var.image_name
  display_name = "VyOS Rolling"
  namespace    = var.image_namespace
  source_type  = "download"
  url          = var.image_url

  lifecycle {
    # URL changes between nightly builds; don't force image re-download on update
    ignore_changes = [url]
  }
}

# ── eth1 trunk network ────────────────────────────────────────────────────────
# eth1 is a raw bridge port — no VLAN filter. Harvester passes all tagged frames
# to VyOS, which handles 802.1Q sub-interfaces (vif) per tenant VLAN.
#
# route_mode = "manual" is required by the Harvester provider when route_cidr
# is specified. The CIDR here is informational only; routing is done by VyOS.
# Using 0.0.0.0/0 to indicate "all tenant subnets pass through this trunk".

resource "harvester_network" "eth1_trunk" {
  name                 = local.trunk_network_name
  namespace            = local.trunk_network_namespace
  vlan_id              = 0
  cluster_network_name = var.cluster_network_name
  route_mode           = "manual"
  route_cidr           = "10.0.0.0/8"
  route_gateway        = "0.0.0.0"
}

# ── VyOS gateway VM ───────────────────────────────────────────────────────────

resource "harvester_virtualmachine" "vyos" {
  name                 = var.vm_name
  namespace            = var.vm_namespace
  cpu                  = var.cpu
  memory               = var.memory
  restart_after_update = true
  run_strategy         = "RerunOnFailure"
  machine_type         = "q35"

  # eth0 — DigiOps/uplink NIC (VLAN 700). Static IP configured post-install.
  network_interface {
    name         = "eth0"
    type         = "bridge"
    network_name = var.uplink_network_name
  }

  # eth1 — tenant trunk NIC. VyOS creates 802.1Q vif sub-interfaces per tenant.
  network_interface {
    name         = "eth1"
    type         = "bridge"
    network_name = "${local.trunk_network_namespace}/${harvester_network.eth1_trunk.name}"
  }

  # Root disk — VyOS is installed here via 'install image' from the ISO.
  disk {
    name        = "rootdisk"
    type        = "disk"
    size        = var.disk_size
    bus         = "virtio"
    boot_order  = var.iso_installed ? 1 : 2
    auto_delete = true
  }

  # CDROM — present only before iso_installed = true.
  # After the second apply this disk block disappears, detaching the CDROM.
  dynamic "disk" {
    for_each = var.iso_installed ? [] : [1]
    content {
      name        = "cdrom"
      type        = "cd-rom"
      size        = "1Gi"
      bus         = "sata"
      boot_order  = 1
      image       = harvester_image.vyos.id
      auto_delete = true
    }
  }

  depends_on = [harvester_network.eth1_trunk]
}
