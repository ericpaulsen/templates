terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.7.0"
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

variable "workspaces_namespace" {
  type        = string
  sensitive   = true
  description = "The namespace to create workspaces in (must exist prior to creating workspaces)"
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

provider "coder" {
  feature_use_managed_variables = false
}

data "coder_parameter" "dotfiles_uri" {
  description = "Dotfiles repo URI (optional)"
  name        = "dotfiles_uri"
  type        = "string"
  mutable     = true
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Container image"
  mutable      = false
  option {
    value = "jupyter/datascience-notebook:latest"
    name  = "jupyter/datascience-notebook"
  }
  option {
    value = "marktmilligan/jupyterlab:latest"
    name  = "marktmilligan/jupyterlab"
  }
  option {
    value = "codercom/enterprise-jupyter:ubuntu"
    name  = "codercom/enterprise-jupyter"
  }
}

data "coder_parameter" "repo" {
  description  = "Code repository to clone (optional)"
  name         = "repo"
  display_name = "Code repository"
  mutable      = true
  option {
    value = "mark-theshark/pandas_automl.git"
    name  = "pandas_automl"
  }
  option {
    value = "mark-theshark/plotly_dash.git"
    name  = "plotly_dash"
  }
}

data "coder_parameter" "cpu" {
  default      = 1
  name         = "cpu"
  display_name = "CPU cores"
  mutable      = false
  option {
    value = "1"
    name  = "1"
  }
  option {
    value = "2"
    name  = "2"
  }
  option {
    value = "4"
    name  = "4"
  }
  option {
    value = "6"
    name  = "6"
  }
  option {
    value = "8"
    name  = "8"
  }
}

data "coder_parameter" "memory" {
  default      = "2"
  name         = "memory"
  display_name = "Memory"
  mutable      = false
  option {
    value = "1"
    name  = "1"
  }
  option {
    value = "2"
    name  = "2"
  }
  option {
    value = "4"
    name  = "4"
  }
  option {
    value = "8"
    name  = "8"
  }
}

data "coder_parameter" "disk_size" {
  default      = "10"
  name         = "disk_size"
  display_name = "Disk size"
  mutable      = false
  option {
    value = "10"
    name  = "10"
  }
  option {
    value = "20"
    name  = "20"
  }
  option {
    value = "30"
    name  = "30"
  }
  option {
    value = "40"
    name  = "40"
  }
  option {
    value = "50"
    name  = "50"
  }
}

data "coder_workspace" "me" {}

resource "coder_agent" "coder" {
  os             = "linux"
  arch           = "amd64"
  dir            = "/home/coder"
  startup_script = <<EOT
#!/bin/bash

# install code-server
curl -fsSL https://code-server.dev/install.sh | sh 2>&1 | tee -a build.log
code-server --auth none --port 13337 2>&1 | tee -a build.log &

# start jupyterlab
jupyter lab --ServerApp.token='' --ip='*' --ServerApp.base_url=/@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}/apps/jupyter-lab/ 2>&1 | tee -a build.log &

# add some Python libraries
pip3 install --user pandas numpy 2>&1 | tee -a build.log

# use coder CLI to clone and install dotfiles
coder dotfiles -y ${data.coder_parameter.dotfiles_uri.value} 2>&1 | tee -a build.log

# clone repo
ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
git clone --progress git@github.com:${data.coder_parameter.repo.value} 2>&1 | tee -a build.log

EOT
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.coder.id
  display_name = "VS Code"
  slug         = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
}

# jupyterlab
resource "coder_app" "jupyter-lab" {
  agent_id     = coder_agent.coder.id
  display_name = "JupyterLab"
  slug         = "jupyter-lab"
  icon         = "/icon/jupyter.svg"
  url          = "http://localhost:8888/@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}/apps/jupyter-lab/"
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
  }
  spec {
    security_context {
      run_as_user = "1000"
      fs_group    = "1000"
    }
    container {
      name              = "jupyterlab"
      image             = "docker.io/${data.coder_parameter.image.value}"
      command           = ["sh", "-c", coder_agent.coder.init_script]
      image_pull_policy = "Always"
      security_context {
        run_as_user = "1000"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.coder.token
      }
      resources {
        requests = {
          cpu    = "250m"
          memory = "250Mi"
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
    name      = "home-coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
}
