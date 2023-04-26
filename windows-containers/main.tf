terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }
}

variable "use_kubeconfig" {
  type        = bool
  sensitive   = true
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

variable "cpu" {
  description = "CPU (__ cores)"
  default     = 1
  validation {
    condition = contains([
      "1",
      "2",
      "4",
      "6"
    ], var.cpu)
    error_message = "Invalid cpu!"
  }
}

variable "memory" {
  description = "Memory (__ GB)"
  default     = 2
  validation {
    condition = contains([
      "1",
      "2",
      "4",
      "8"
    ], var.memory)
    error_message = "Invalid memory!"
  }
}

variable "disk_size" {
  description = "Disk size (__ GB)"
  default     = 10
}

resource "coder_agent" "coder" {
  os   = "windows"
  arch = "amd64"
  dir  = "/home/coder"
}

resource "kubernetes_secret" "init_script" {
  metadata {
    name      = "coder-init-script"
    namespace = "oss"
  }
  type = "Opaque"
  data = {
    "init.ps1" = base64encode(coder_agent.coder.init_script)
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim.home-directory
  ]
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "oss"
  }
  spec {
    node_selector = {
      "windows" = "true"
    }
    toleration {
      key      = "windows"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
    toleration {
      key      = "node.kubernetes.io/os"
      operator = "Equal"
      value    = "windows"
      effect   = "NoSchedule"
    }
    container {
      name              = "coder-container"
      image             = "ericpaulsen/node-windows:v1"
      image_pull_policy = "Always"
      command           = ["C:\\coder_init\\init.ps1"]
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.coder.token
      }
      resources {
        requests = {
          cpu    = "250m"
          memory = "500Mi"
        }
        limits = {
          cpu    = "${var.cpu}"
          memory = "${var.memory}G"
        }
      }
      volume_mount {
        mount_path = "/home/coder"
        name       = "home-directory"
      }
      volume_mount {
        mount_path = "C:\\coder_init"
        name       = "coder-init-script"
      }
    }
    volume {
      name = "home-directory"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home-directory.metadata.0.name
      }
    }
    volume {
      name = "coder-init-script"
      secret {
        secret_name = "coder-init-script"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "home-directory" {
  metadata {
    name      = "home-coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "oss"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "standard-windows"
    resources {
      requests = {
        storage = "${var.disk_size}Gi"
      }
    }
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.main[0].id
  item {
    key   = "CPU"
    value = "${var.cpu} cores"
  }
  item {
    key   = "memory"
    value = "${var.memory}GB"
  }
  item {
    key   = "CPU requests"
    value = kubernetes_pod.main[0].spec[0].container[0].resources[0].requests.cpu
  }
  item {
    key   = "memory requests"
    value = kubernetes_pod.main[0].spec[0].container[0].resources[0].requests.memory
  }
  item {
    key   = "disk"
    value = "${var.disk_size}GiB"
  }
  item {
    key   = "volume"
    value = kubernetes_pod.main[0].spec[0].container[0].volume_mount[0].mount_path
  }
}
