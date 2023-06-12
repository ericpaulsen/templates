terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }
}

provider "coder" {
  feature_use_managed_variables = true
}

provider "kubernetes" {
}

data "coder_workspace" "me" {}

data "coder_parameter" "namespace" {
  name    = "namespace"
  type    = "string"
  default = "eric-oss"
  icon    = "${data.coder_workspace.me.access_url}/icon/k8s.png"
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

export PATH="$HOME/.local/bin:$PATH"

# start code-server
code-server --auth none --port 13337  >/dev/null 2>&1 &

# start airflow
airflow standalone >/dev/null 2>&1 &

  EOT  
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.coder.id
  slug         = "code-server"
  display_name = "VS Code Browser"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# airflow
resource "coder_app" "airflow" {
  agent_id     = coder_agent.coder.id
  slug         = "airflow"
  display_name = "Apache Airflow"
  icon         = "https://www.vhv.rs/dpng/d/518-5188627_apache-airflow-documentation-airflow-documentation-apache-airflow-logo.png"
  url          = "http://localhost:8080/"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/healthz"
    interval  = 5
    threshold = 20
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
      run_as_user  = 1000
      run_as_group = 1000
    }
    container {
      name              = "coder-container"
      image             = "docker.io/ericpaulsen/code-server-airflow:latest"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.coder.init_script]
      security_context {
        run_as_user  = 1000
        run_as_group = 1000
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
    }
    volume {
      name = "home-directory"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home-directory.metadata.0.name
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
    value = "docker.io/ericpaulsen/code-server-airflow:latest"
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
