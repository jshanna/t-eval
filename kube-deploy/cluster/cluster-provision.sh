#!/bin/bash
DEBIAN_FRONTEND=noninteractive
KERNEL_MODULES=('overlay' 'br_netfilter')
SYSCTL_PARAMS=('net.bridge.bridge-nf-call-iptables=1' 'net.bridge.bridge-nf-call-ip6tables=1' 'net.ipv4.ip_forward=1')

# Load config file
declare -A config

CONFIG_FILE="settings.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file $CONFIG_FILE not found." >&2
    exit 1
fi

while IFS='=' read -r key value || [[ -n "$key" ]]; do
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    if [[ -z "$key" || "$key" =~ ^# ]]; then
        continue
    fi

    config["$key"]="$value"

done < "$CONFIG_FILE"

IFS=', ' read -r -a worker_node_array <<< "${config[worker_nodes]}"
declare -a node_array
node_array=(${config[control_node]} ${worker_node_array[@]})
echo "Current Config Values:"
echo "Control Node: ${config[control_node]}"
echo "Worker Nodes: ${config[worker_nodes]}"
echo "SSH User: ${config[ssh_user]}"
echo "SSH Key Path: ${config[ssh_key_path]}"
echo "Pod CIDR: ${config[pod_network_cidr]}"
echo "Service CIDR: ${config[service_cidr]}"
echo "Kubernetes Version: ${config[kube_version]}"

function run_ssh_command () {
    response=$(ssh -i ${config[ssh_key_path]} ${config[ssh_user]}@$1 $2)
    echo $response
}

# Pre-flight
for node in ${node_array[@]}; do
    # echo "Performing pre-flight steps on: $node"
    # ## Update Apt Cache
    # run_ssh_command $node "sudo apt update"
    # ## Install required Packages
    # run_ssh_command $node "sudo apt install -y apt-transport-https ca-certificates curl gnupg conntrack socat ipset"
    # ## Disable Swap
    # run_ssh_command $node "sudo swapoff -a"
    # run_ssh_command $node "sudo sed -i '/swap/d' /etc/fstab"
    # ## Enabled Required Kernel Modules
    # run_ssh_command $node "sudo touch /etc/modules-load.d/k8s.conf"
    # for mod in ${KERNEL_MODULES[@]}; do
    #     run_ssh_command $node "sudo modprobe $mod"
    #     run_ssh_command $node "echo $mod | sudo tee -a /etc/modules-load.d/k8s.conf"
    # done
    # ## Set sysctl Parameters
    # run_ssh_command $node "sudo touch /etc/sysctl.d/k8s.conf"
    # for sp in ${SYSCTL_PARAMS[@]}; do
    #     run_ssh_command $node "sudo sysctl -w $sp"
    #     run_ssh_command $node "echo $sp | sudo tee -a /etc/sysctl.d/99-k8s.conf"
    # done
    # run_ssh_command $node "sudo sysctl --system"
    ## Install Docker
    # node_arch=$(run_ssh_command $node 'dpkg --print-architecture')
    # run_ssh_command $node "sudo install -m 07555 -d /etc/apt/keyrings"
    # run_ssh_command $node "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    # run_ssh_command $node "sudo chmod a+r /etc/apt/keyrings/docker.asc"
    # run_ssh_command $node "echo 'Types: deb' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "echo 'URIs: https://download.docker.com/linux/ubuntu' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "echo 'Suites: noble' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "echo 'Components: stable' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "echo 'Architectures: $node_arch' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "echo 'Signed-By: /etc/apt/keyrings/docker.asc'| sudo tee -a /etc/apt/sources.list.d/docker.sources"
    # run_ssh_command $node "sudo apt update"
    # run_ssh_command $node "sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    # run_ssh_command $node "sudo systemctl start docker"
    ## Install Kubernetes
    run_ssh_command $node "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${config[kube_version]}"/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    echo
done



## Install Kubernetes

# test_out="$(run_ssh_command '192.168.1.21' 'df -h')"
# echo $test_out

# Controller node
## initialize control plane


## capture/parse results load into variables
# kubeadm init --pod-network-cidr={{ pod_network_cidr }} --service-cidr={{ service_cidr }}
# kubeadm token create --print-join-command

## capture admin kube config
# - name: Create .kube directory for root
#   file:
#     path: /root/.kube
#     state: directory
#     mode: '0755'

# - name: Copy admin.conf to root's .kube directory
#   copy:
#     src: "{{ kubeconfig_path }}"
#     dest: /root/.kube/config
#     remote_src: yes
#     mode: '0600'

## Install Calico
## Wait for Control Plane
## Generate and store join command
## install local-path-provisioner for storage
## create app-deploy user and capture config

# Worker nodes
## Check if node has already joined
## Run Join Command
## Wait for workers to be ready
## Done