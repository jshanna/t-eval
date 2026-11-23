#!/usr/bin/env bash
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
declare -A node_array
#node_array=(${config[control_node]} ${worker_node_array[@]})
node_array+="${config[control_node]} "
node_array+="${worker_node_array[@]}"

echo "Current Config Values:"
echo "  Control Node: ${config[control_node]}"
echo "  Worker Nodes: ${config[worker_nodes]}"
echo "  SSH User: ${config[ssh_user]}"
echo "  SSH Key Path: ${config[ssh_key_path]}"
echo "  Pod CIDR: ${config[pod_network_cidr]}"
echo "  Service CIDR: ${config[service_cidr]}"
echo "  Kubernetes Version: ${config[kube_version]}"
echo "  Calico Version: ${config[calico_version]}"

function run_ssh_command () {
    response=$(ssh -i ${config[ssh_key_path]} ${config[ssh_user]}@$1 $2)
    echo $response
}

function get_service_status () {
    service_status=$(run_ssh_command $node "sudo systemctl status $1 | grep Active | xargs")
    echo "$1 Status: $service_status"
}

# Pre-flight
echo
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

    # # Install Docker
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
    # get_service_status "docker"
    # run_ssh_command $node "sudo chmod 664 /etc/containerd/config.toml"
    # run_ssh_command $node "sudo containerd config default > /etc/containerd/config.toml"
    # run_ssh_command $node "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml"
    # run_ssh_command $node "sudo chmod 644 /etc/containerd/config.toml"
    # run_ssh_command $node "sudo systemctl restart containerd"
    # get_service_status "containerd"

    ## Install Kubernetes
    # run_ssh_command $node "sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v${config[kube_version]}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    # kube_package_string="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${config[kube_version]}/deb/ /"
    # run_ssh_command $node "echo $kube_package_string | sudo tee -a /etc/apt/sources.list.d/kubernetes.list"
    # run_ssh_command $node "sudo apt update"
    # run_ssh_command $node "sudo apt install -y kubelet kubeadm kubectl"
    # run_ssh_command $ndoe "sudo apt-mark hold kubelet kubeadm kubectl"
    # run_ssh_command $node "sudo systemctl enable kubelet"
    # run_ssh_command $node "sudo systemctl start kubelet"

    echo
done

# Controller node
## initialize control plane
# run_ssh_command ${config[control_node]} "sudo kubeadm init --pod-network-cidr=${config[pod_network_cidr]} --service-cidr=${config[service_cidr]}"

## Enable User/Root Kube config
# run_ssh_command ${config[control_node]} "sudo mkdir /root/.kube"
# run_ssh_command ${config[control_node]} "sudo cp /etc/kubernetes/admin.conf /root/.kube/config"
# run_ssh_command ${config[control_node]} "sudo chmod 755 /root/.kube"
# run_ssh_command ${config[control_node]} "sudo chmod 600 /root/.kube"
# run_ssh_command ${config[control_node]} "sudo mkdir /home/$USER/.kube"
# run_ssh_command ${config[control_node]} "sudo cp /etc/kubernetes/admin.conf /home/$USER/.kube/config"
# run_ssh_command ${config[control_node]} "sudo chown -R $USER:$USER /home/$USER/.kube"
# run_ssh_command ${config[control_node]} "sudo chmod 755 /home/$USER/.kube"
# run_ssh_command ${config[control_node]} "sudo chmod 600 /home/$USER/.kube/config"
kube_join_cmd=$(run_ssh_command ${config[control_node]} "sudo kubeadm token create --print-join-command")

## Install Calico CNI
tigera_url="https://raw.githubusercontent.com/projectcalico/calico/${config[calico_version]}/manifests/tigera-operator.yaml"
calico_url="https://raw.githubusercontent.com/projectcalico/calico/${config[calico_version]}/manifests/custom-resources.yaml"
pod_network_string=${config[pod_network_cidr]}
sed_network_string="${pod_network_string//./\\.}"
sed_network_string="${sed_network_string////\\/}"

# run_ssh_command ${config[control_node]} "sudo kubectl create -f $tigera_url"
# run_ssh_command ${config[control_node]} "sudo curl -fsSL $calico_url -o /tmp/calico-custom-resources.yaml"
# run_ssh_command ${config[control_node]} "sudo chmod 664 /tmp/calico-custom-resources.yaml"
# run_ssh_command ${config[control_node]} "sudo sed -i "s@192\.168\.0\.0\/16@$sed_network_string@g" /tmp/calico-custom-resources.yaml"
# run_ssh_command ${config[control_node]} "sudo kubectl create -f /tmp/calico-custom-resources.yaml"

## Wait for Calico to be ready
# sleep 30
# run_ssh_command ${config[control_node]} "kubectl wait --namespace calico-system --for=condition=ready pod --selector=k8s-app=calico-node --timeout=300s"

## Wait for control plane to be ready
# cp_status=$(run_ssh_command ${config[control_node]} "kubectl get nodes | sed -n '2p'")
# cp_status=$(echo $cp_status | awk '{print $2}')
# printf "Waiting for Control Plane to be ready"
# while [[ "$cp_status" != "Ready" ]]; do
#     cp_status=$(run_ssh_command ${config[control_node]} "kubectl get nodes | sed -n '2p'")
#     cp_status=$(echo $cp_status | awk '{print $2}')
#     printf "."
#     sleep 5
# done
# echo
# echo "Control Plane: $cp_status"

## install local-path-provisioner for storage
# run_ssh_command ${config[control_node]} "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml"
# run_ssh_command ${config[control_node]} "kubectl patch storageclass local-path -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"

# Worker nodes
for node in ${worker_node_array[@]}; do
    node_join_check=$(run_ssh_command $node "[ -f '/etc/kubernetes/kubelet.conf' ] && echo 'Joined'")
    if [[ "$node_join_check" == "Joined" ]]; then
        echo "$node already joined to Kubernetes cluster"
    else
        echo "Joining $node to cluster..."
        run_ssh_command $node "sudo $kube_join_cmd"
    fi
done

## Check if node has already joined
## Run Join Command
## Wait for workers to be ready
## Done

## create app-deploy user and capture config

# test_out="$(run_ssh_command '192.168.1.21' 'df -h')"
# echo $test_out