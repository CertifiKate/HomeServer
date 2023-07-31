
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.5.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.20.2"
    }
  }
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

# Get gotfiles for this user
variable "dotfiles_uri" {
  description = <<-EOF
  Dotfiles repo URI (optional)
  see https://dotfiles.github.io
  EOF
  default     = ""
}


resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  startup_script = <<EOT
    #!/bin/bash
    # Add dotfiles
    coder dotfiles -y ${var.dotfiles_uri}

    /usr/lib/code-server/bin/code-server --auth none --port 13337 | tee /tmp/code-server.log

  EOT
}

resource "coder_app" "code-server" {
  agent_id = coder_agent.main.id
  name     = "code-server"
  url      = "http://localhost:13337/?folder=/home/coder"
  icon     = "/icon/code.svg"
}

variable "docker_image" {
  description = "What Docker image would you like to use for your workspace?"
  default     = "base"

  # List of images available for the user to choose from.
  validation {
    condition     = contains(["base", "go"], var.docker_image)
    error_message = "Invalid Docker image!"
  }

  # Prevents admin errors when the image is not found
  validation {
    condition     = fileexists("images/${var.docker_image}.Dockerfile")
    error_message = "Invalid Docker image. The file does not exist in the images directory."
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-root"
}

resource "docker_image" "coder_image" {
  name = "coder-base-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  build {
    path       = "./images/"
    dockerfile = "${var.docker_image}.Dockerfile"
    tag        = ["coder-${var.docker_image}:v0.1.20"]
  }

  # Keep alive for other workspaces to use upon deletion
  keep_locally = true
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.coder_image.latest
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = lower(data.coder_workspace.me.name)
  # Use the docker gateway if the access URL is 127.0.0.1
  #command = ["while true; do sleep 1; done"]
  command = ["sh", "-c", replace(coder_agent.main.init_script, "127.0.0.1", "host.docker.internal"), "& while true; do sleep 1; done"]
  env     = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}", 
    "USER=${data.coder_workspace.me.owner}", 
    "DOTFILES_USE_MOTD=true" 
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "image"
    value = var.docker_image
  }
}
