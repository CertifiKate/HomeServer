
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.7.0"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

data "coder_workspace" "me" {
}

resource "coder_agent" "main" {
  auth                   = "token"
  arch                   = "amd64"
  os                     = "linux"
  login_before_ready     = true
  env = {
    DOTFILES_USES_MOTD   = true
    DOTFILES_REPO         = data.coder_parameter.dotfiles_url.value != "" ? "coder dotfiles -y ${data.coder_parameter.dotfiles_url.value}" : ""
  }
  startup_script_timeout = 180
  startup_script         = <<-EOT
    /bin/bash -c "

    # Apply dotfiles using chezmoi
    if [ ! "$DOTFILES_REPO" == "" ]; then
      if [ ! -x "$(command -v chezmoi)" ]; then
              echo "Installing chezmoi"
              sudo sh -c "$(curl -fsLS get.chezmoi.io)" -b /usr/local/bin
              /usr/local/bin chezmoi init $DOTFILES_REPO
      fi
      chezmoi update
    fi

    # Install code server
    CODE_SERVER_VERSION='4.12.0'
    INSTALL_CODE_SERVER='false'

    if [ ! -x '$(command -v code-server)' ]; then
            echo 'Installing code-server'
            INSTALL_CODE_SERVER='true'
    else
            INSTALLED_VERSION=$(dpkg-query -W -f '$${version}\n' code-server)

            if [ $CODE_SERVER_VERSION != $INSTALLED_VERSION ]; then
                    INSTALL_CODE_SERVER='true'
                    echo 'Updating code server'
            fi
    fi

    if [ '$INSTALL_CODE_SERVER' == 'true' ]; then
      curl -fsSL https://code-server.dev/install.sh | sh
    fi

    # Start code server
    pkill --signal TERM code-server
    code-server --auth none --port 13337 &"
  EOT

}


resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${lower(data.coder_workspace.me.owner)}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}


data "coder_parameter" "ip" {
  name        = "IP ending"
  type        = "number"
  description = "Ip will end in 10.0.101.x"
  mutable     = false
  default     = 20
  validation {
    min       = 20
    max       = 255
  }
}

data "coder_parameter" "ctid" {
  name        = "CT Id"
  type        = "number"
  description = "Number of compute instances"
  mutable     = false
  default     = 500
  validation {
    min       = 500
    max       = 599
  }
}

provider "coder" {
  url = "http://10.0.101.3:7080"
}

provider "proxmox" {
  pm_api_url = "https://{{ hostvars["microwave"].ansible_host }}:8006/api2/json"
  pm_api_token_id = "{{ vault_coder_proxmox_token_id }}"
  pm_api_token_secret = "{{ vault_coder_proxmox_token_secret }}"
}

data "coder_parameter" "dotfiles_url" {
  name        = "dotfiles URL"
  description = "Git repository with dotfiles"
  mutable     = true
  default     = ""
}

data "coder_parameter" "disk_size" {
  default = 4
  type = "number"
  name = "Disk Size (GB)"
  mutable = true
  validation {
    min = 2
    max = 10
    monotonic = "increasing"
  }
}

data "coder_parameter" "cpu_cores" {
  default = 1
  type = "number"
  name = "CPU Cores"
  mutable = true
  validation {
    min = 1
    max = 4
  }
}

data "coder_parameter" "memory" {
  default = "512"
  name = "Memory"
  mutable = true
  option {
    name = "512MB"
    value = "512"
  }
  option {
    name = "1GB"
    value = "1024"
  }
  option {
    name = "2GB"
    value = "2048"
  }
  option {
    name = "3GB"
    value = "3072"
  }
  option {
    name = "4GB"
    value = "4096"
  }
}

resource "proxmox_lxc" "container" {
  count         = 1
  vmid          = data.coder_parameter.ctid.value
  // A bit of a hack - see if there's a better way to do this
  hastate       = data.coder_workspace.me.transition == "stop" ? "stopped" : "started"
  target_node   = "microwave"
  pool          = "coder"
  hostname      = "${lower(data.coder_workspace.me.name)}-coder"
  ostemplate    = "local:vztmpl/debian-11-standard_11.3-1_amd64.tar.zst"
  unprivileged  = true
  start         = true

  ssh_public_keys = <<-EOT
    {{ vault_coder_ssh_key_pub }}
  EOT

  memory = data.coder_parameter.memory.value
  cores = data.coder_parameter.cpu_cores.value
  swap = 512

  // Terraform will crash without rootfs defined
  rootfs {
    storage = "local-lvm"
    size    = "${data.coder_parameter.disk_size.value}G"
  }

  features {
      nesting = true
  }

  network {
    name   = "eth0"
    bridge = "vmbr101"
    ip     = "10.0.101.${data.coder_parameter.ip.value}/24"
    gw     = "10.0.101.1"
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = "10.0.101.${data.coder_parameter.ip.value}"
    private_key = file("/home/coder/.ssh/coder-key")
  }

  # Run one-time setup scripts
  provisioner "remote-exec" {
    inline = [ 
    # Add curl and sudo
    <<-EOT
    apt update;
    apt install curl sudo git zsh -y;
    EOT

    ,

    # Install coder
    "curl -fsSL https://coder.com/install.sh | sh"
    ,

    # Add line to hosts to direct to prox-01
    <<-EOT
    LINE='10.0.101.3      code.{{ project_tld }}'; FILE='/etc/hosts'; grep -qF -- '$LINE' $FILE || echo $LINE >> $FILE
    EOT

    ,

    # Create user
    "useradd -s /bin/zsh -m -G sudo ${lower(data.coder_workspace.me.owner)}"
    
    ,
    
    # Give user passwordless sudo rights
    "echo '${lower(data.coder_workspace.me.owner)}	ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers"
    ]
  }
}

# Run the coder agent
resource "null_resource" "run_startup_script" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    proxmox_lxc.container,
    coder_agent.main
  ]
  
  triggers = {
    always_run = "${timestamp()}"
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = "10.0.101.${data.coder_parameter.ip.value}"
    private_key = file("/home/coder/.ssh/coder-key")
  }

  # Hacky work around to get coder agent starting properly. Can't seem to update the script and token without doing it this way
  # TODO: Investigate if we can get token from file generated on workspace create/start
  provisioner "remote-exec" {
    inline = [ 
    <<-EOT
    cat > /coder-startup.sh <<'EOL'
    ${coder_agent.main.init_script}
    EOL
    
    chmod 755 /coder-startup.sh
    EOT
    ,

    <<-EOT
    cat > /etc/init.d/coder-startup <<'EOL'
    #! /bin/bash
    ### BEGIN INIT INFO
    # Provides:       coder-startup
    # Required-Start:    \$local_fs \$syslog
    # Required-Stop:     \$local_fs \$syslog
    # Default-Start:     2 3 4 5
    # Default-Stop:      0 1 6
    # Short-Description: starts coder-startup
    # Description:       starts coder-startup using start-stop-daemon
    ### END INIT INFO
    /bin/su ${lower(data.coder_workspace.me.owner)} -c 'CODER_AGENT_TOKEN=${coder_agent.main.token} /coder-startup.sh &'
    exit 0
    EOL

    chmod 755 /etc/init.d/coder-startup
    update-rc.d coder-startup defaults
    systemctl restart coder-startup
    EOT

    ]
  }
}