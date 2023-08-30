terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }
}

provider "coder" {}

provider "kubernetes" {
  #config_path = "~/.kube/config"
}

data "coder_workspace" "me" {}

data "coder_parameter" "namespace" {
  name    = "namespace"
  type    = "string"
  default = "coder"
  icon    = "${data.coder_workspace.me.access_url}/icon/k8s.png"
}

data "coder_parameter" "image" {
  name = "image"
  type = "string"
  icon = "${data.coder_workspace.me.access_url}/icon/docker.png"
  option {
    value = "codercom/enterprise-node:ubuntu"
    name  = "node"
  }
  option {
    value = "codercom/enterprise-golang:ubuntu"
    name  = "golang"
  }
  option {
    value = "codercom/enterprise-java:ubuntu"
    name  = "java"
  }
  option {
    value = "codercom/enterprise-base:ubuntu"
    name  = "base"
  }
}

data "coder_parameter" "cpu" {
  name = "cpu"
  icon = "https://cdn-icons-png.flaticon.com/512/4617/4617522.png"
  option {
    value = "2"
    name  = "2 cores"
  }
  option {
    value = "4"
    name  = "4 cores"
  }
  option {
    value = "6"
    name  = "6 cores"
  }
  option {
    value = "8"
    name  = "8 cores"
  }
}

data "coder_parameter" "memory" {
  name = "memory"
  icon = "https://cdn-icons-png.flaticon.com/512/74/74150.png"
  option {
    value = "2"
    name  = "2 GB"
  }
  option {
    value = "4"
    name  = "4 GB"
  }
  option {
    value = "6"
    name  = "6 GB"
  }
  option {
    value = "8"
    name  = "8 GB"
  }
}

data "coder_parameter" "disk_size" {
  name = "disk_size"
  icon = "https://cdn-icons-png.flaticon.com/512/4891/4891697.png"
  option {
    value = "10"
    name  = "10 GB"
  }
  option {
    value = "20"
    name  = "20 GB"
  }
  option {
    value = "30"
    name  = "30 GB"
  }
  option {
    value = "40"
    name  = "40 GB"
  }
}

resource "coder_agent" "coder" {
  os             = "linux"
  arch           = "amd64"
  dir            = "/home/coder"
  startup_script = <<EOT
#!/bin/bash

# install code-server
curl -fsSL https://code-server.dev/install.sh | sh
code-server --auth none --port 13337 >/dev/null 2>&1 &

  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }


  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }


  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }


  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }


  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }


  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.coder.id
  slug         = "code-server"
  display_name = "VS Code Browser"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8000?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim.home-directory
  ]
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = data.coder_parameter.namespace.value
  }
  spec {
    security_context {
      run_as_user = "1000"
      fs_group    = "1000"
    }
    container {
      name              = "coder-container"
      image             = "codercom/enterprise-base:ubuntu"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.coder.init_script]
      security_context {
        run_as_user = "1000"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.coder.token
      }
      env {
        name  = "CODER_USER_EMAIL"
        value = data.coder_workspace.me.owner_email
      }
      resources {
        requests = {
          cpu    = "250m"
          memory = "500Mi"
        }
        limits = {
          cpu    = "${data.coder_parameter.cpu.value}"
          memory = "${data.coder_parameter.memory.value}G"
        }
      }
      volume_mount {
        mount_path = "/home/coder"
        name       = "home-directory"
      }
      # the Storage Account will be mounted at /blob inside of the container
      volume_mount {
        mount_path = "/blob"
        name       = "blob-storage"
      }
    }
    volume {
      name = "home-directory"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home-directory.metadata.0.name
      }
    }
    # here is the volume definition for the Azure Blob Storage Account. We are passing in the disk URI and name from the parameters set above
    volume {
      name = "blob-storage"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.azure-blob.metadata.0.name
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "home-directory" {
  metadata {
    name      = "home-coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = data.coder_parameter.namespace.value
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "azure-blob" {
  metadata {
    name      = "azure-blob-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = data.coder_parameter.namespace.value
  }
  wait_until_bound = false
  spec {
    volume_name = "pv-blob"
    # must match the StorageClass set on PV
    storage_class_name = "azureblob-fuse-premium"
    # must match the AccessMode set on PV
    access_modes = ["ReadOnlyMany"]
    resources {
      requests = {
        # must match size of PV
        storage = "10Gi"
      }
    }
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.main[0].id
  item {
    key   = "CPU"
    value = "${data.coder_parameter.cpu.value} cores"
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory.value}GB"
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
    key   = "image"
    value = kubernetes_pod.main[0].spec[0].container[0].image
  }
  item {
    key   = "disk"
    value = "${data.coder_parameter.disk_size.value}GiB"
  }
  item {
    key   = "volume"
    value = kubernetes_pod.main[0].spec[0].container[0].volume_mount[0].mount_path
  }
}
