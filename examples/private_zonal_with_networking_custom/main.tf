/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

terraform {
  backend "gcs" {
    bucket = "terraform-state-devs"
    #terraform/state/<project>
    prefix = "terraform/state/gke-dev-3"
  }
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gcp-network" {
  source  = "terraform-google-modules/network/google"
  version = ">= 7.5"

  project_id   = var.project_id
  network_name = var.network

  subnets = [
    {
      subnet_name           = var.subnetwork
      subnet_ip             = "10.0.0.0/17"
      subnet_region         = var.region
      subnet_private_access = "true"
    },
  ]

  secondary_ranges = {
    (var.subnetwork) = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = "192.168.0.0/18"
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = "192.168.64.0/18"
      },
    ]
  }
}

resource "google_compute_router" "router" {
  name    = "nat-router"
  network = module.gcp-network.network_name
  region  = var.region
  project = var.project_id
}

resource "google_compute_project_default_network_tier" "default" {
  network_tier = "STANDARD"
  project      = var.project_id

}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-gateway"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = var.project_id

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}


data "google_compute_subnetwork" "subnetwork" {
  name       = var.subnetwork
  project    = var.project_id
  region     = var.region
  depends_on = [module.gcp-network]
}

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 31.0"

  project_id = var.project_id
  name       = var.cluster_name
  regional   = false
  region     = var.region
  zones      = slice(var.zones, 0, 1)

  network                              = module.gcp-network.network_name
  subnetwork                           = module.gcp-network.subnets_names[0]
  ip_range_pods                        = var.ip_range_pods_name
  ip_range_services                    = var.ip_range_services_name
  enable_cost_allocation               = true
  monitoring_enable_managed_prometheus = true
  create_service_account               = true
  enable_private_endpoint              = false
  enable_private_nodes                 = true
  master_ipv4_cidr_block               = "172.16.0.0/28"
  deletion_protection                  = false
  remove_default_node_pool             = true
  master_authorized_networks = [
    {
      cidr_block   = data.google_compute_subnetwork.subnetwork.ip_cidr_range
      display_name = "VPC"
    },
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "allow all"
    },
  ]

  node_pools = [
    {
      name         = "pool-01"
      machine_type = "e2-medium"
      # node_locations            = "${var.region}-b,${var.region}-a"
      autoscaling = true
      # node_count   = 0
      min_count    = 0
      max_count    = 1
      disk_type    = "pd-standard"
      disk_size_gb = 10
      auto_upgrade = true
      # service_account = var.compute_engine_service_account
    },
    {
      name         = "pool-02"
      machine_type = "e2-medium"
      #node_locations            = "${var.region}-b,${var.region}-a"
      autoscaling = true
      # node_count   = 0
      min_count    = 0
      max_count    = 1
      disk_type    = "pd-standard"
      disk_size_gb = 10
      auto_upgrade = true
      # service_account = var.compute_engine_service_account
    },
  ]

  node_pools_labels = {
    all = {
      all-pools-example  = true
      all-pools-example2 = true
    }
    pool-01 = {
      pool-01-example = true
    }
    pool-02 = {
      pool-02-example1 = true
      pool-02-example2 = true
    }
  }

  node_pools_taints = {
    # all = [
    #   {
    #     key    = "all-pools-example"
    #     value  = true
    #     effect = "PREFER_NO_SCHEDULE"
    #   },
    # ]
    # pool-01 = [
    #   {
    #     key    = "pool-01-example"
    #     value  = true
    #     effect = "PREFER_NO_SCHEDULE"
    #   },
    # ]
    # pool-02 = [
    #   {
    #     key    = "pool-02-example"
    #     value  = true
    #     effect = "PREFER_NO_SCHEDULE"
    #   },
    #   {
    #     key    = "pool-02-example2"
    #     value  = true
    #     effect = "PREFER_NO_SCHEDULE"
    #   },
    # ]
  }

  node_pools_tags = {
    all = [
      "all-node-example",
    ]
    pool-01 = [
      "pool-01-example",
    ]
    pool-02 = [
      "pool-02-example1",
      "pool-02-example2",

    ]
  }


}

locals {
  namespace = "proxy"
}

resource "kubernetes_namespace" "nginx-example" {
  metadata {
    name = local.namespace
  }
}

# resource "kubernetes_replication_controller" "nginx-example" {
#   metadata {
#     name = "nginx-example"
#   }
#   spec {
#     selector = {
#       "app" = "nginx-example"
#     }
#     replicas = 2
#     template {
#       metadata {
#         name = "nginx-example"
#       }
#       spec {

#       }
#     }
#   }
# }

resource "kubernetes_pod" "nginx-example" {
  metadata {
    name      = "nginx-example"
    namespace = local.namespace
    labels = {
      maintained_by = "terraform"
      app           = "nginx-example"
    }
  }
  spec {
    container {
      image = "nginx:latest"
      name  = "nginx-example"
    }
    # toleration {
    #   effect = "PreferNoSchedule"
    #   key    = "all-pools-example"
    #   value  = "true"
    # }
    # toleration {
    #   effect = "PreferNoSchedule"
    #   key    = "pool-01-example"
    #   value  = "true"
    # }
    # node_selector = {
    #   "pool-02-example"    = "true"
    #   "all-pools-example2" = "true"

    # }
    affinity {
      node_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 60
          preference {
            match_expressions {
              key      = "pool-02-example2"
              operator = "In"
              values   = ["true"]
            }
          }
        }
        preferred_during_scheduling_ignored_during_execution {
          weight = 40
          preference {
            match_expressions {
              key      = "pool-01-example"
              operator = "In"
              values   = ["true"]
            }
          }
        }
      }
    }
  }

  depends_on = [module.gke]
}

resource "kubernetes_service" "nginx-example" {
  metadata {
    name = "terraform-example"
  }

  spec {
    selector = {
      app = kubernetes_pod.nginx-example.metadata[0].labels.app
    }

    session_affinity = "ClientIP"

    port {
      port        = 8080
      target_port = 80
    }

    type = "LoadBalancer"
  }

  depends_on = [module.gke]
}
