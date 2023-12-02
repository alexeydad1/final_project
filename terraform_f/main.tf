// yandex terraform provider
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}
// DataSource networks
data "yandex_vpc_network" "bingonetwork" {
  network_id = "enp6j1s93mkiirsatutl"
}

data "yandex_vpc_subnet" "bingonetwork" {
  subnet_id = "e9bo141jd0u7grup8p2h"
}

// network
//resource "yandex_vpc_network" "bingonetwork" {
# }

# resource "yandex_vpc_subnet" "bingonetwork" {
#   zone           = "ru-central1-a"
#   network_id     = "enp6j1s93mkiirsatutl"
#   v4_cidr_blocks = ["10.128.0.0/24"]
# }

// registry
resource "yandex_container_registry" "bingo-registry" {
  name = "bingo-registry"
}

// variables
locals {
  folder_id = "b1g7n7r7sqst0vi1d64b"
  service-accounts = toset([
    "bingo-sa",
    "bingo-ig-sa",
  ])
  bingo-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
    "editor"
  ])
  bingo-ig-sa-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",
    "vpc.user",
    "editor"
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "bingo-roles" {
  for_each  = local.bingo-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-sa"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "bingo-ig-roles" {
  for_each  = local.bingo-ig-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-ig-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

// instance group Application
resource "yandex_compute_instance_group" "bingoapp" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.bingo-ig-roles,
  ]
  name               = "bingoapp"
  service_account_id = yandex_iam_service_account.service-accounts["bingo-ig-sa"].id
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["bingo-sa"].id
    resources {
      cores         = 2
      memory        = 2
      core_fraction = 100
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = data.yandex_vpc_network.bingonetwork.id
      subnet_ids = ["${data.yandex_vpc_subnet.bingonetwork.id}"]
      nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile(
        "${path.module}/docker-compose.yaml",
        {
          folder_id   = "${local.folder_id}",
          registry_id = "${yandex_container_registry.bingo-registry.id}",
        }
      )
      user-data = file("${path.module}/cloud-config.yaml")
      ssh-keys  = "ubuntu:${file("~/devops_training.pub")}"
    }
  }
  load_balancer {
    target_group_name = "bingoapp"
  }
}


resource "yandex_lb_network_load_balancer" "lbbingo" {
  name = "lbbingo"

  listener {
    name        = "bingolistener"
    port        = 80
    target_port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.bingoapp.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}