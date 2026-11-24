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
node_array+="${config[control_node]} "
node_array+="${worker_node_array[@]}"

echo "Current Config Values:"
echo "  Control Node: ${config[control_node]}"
echo "  Worker Nodes: ${config[worker_nodes]}"
echo "  SSH User: ${config[ssh_user]}"
echo "  SSH Key Path: ${config[ssh_key_path]}"
echo
echo "  Pod CIDR: ${config[pod_network_cidr]}"
echo "  Service CIDR: ${config[service_cidr]}"
echo
echo "  Kubernetes Version: ${config[kube_version]}"
echo "  Calico Version: ${config[calico_version]}"
echo "  Metallb Version: ${config[metallb_version]}"
echo "  Kgateway Version: ${config[kgateway_version]}"
echo "  Cert-Manager Version: ${config[cert_manager_version]}"

function run_ssh_command () {
    response=$(ssh -i ${config[ssh_key_path]} ${config[ssh_user]}@$1 $2)
    echo $response
}

function get_service_status () {
    service_status=$(run_ssh_command $node "sudo systemctl status $1 | grep Active | xargs")
    echo "$1 Status: $service_status"
}

function sftp_put () {
    sftp -i ${config[ssh_key_path]} ${config[ssh_user]}@$1 <<< "put $2 $3"
}

# Pre-flight
echo
for node in ${node_array[@]}; do
    echo "Performing pre-flight steps on: $node"
    
    ## Update Apt Cache
    run_ssh_command $node "sudo apt update"

    ## Install required Packages
    run_ssh_command $node "sudo apt install -y apt-transport-https ca-certificates curl gnupg conntrack socat ipset"
    
    ## Disable Swap
    run_ssh_command $node "sudo swapoff -a"
    run_ssh_command $node "sudo sed -i '/swap/d' /etc/fstab"

    ## Enabled Required Kernel Modules
    run_ssh_command $node "sudo touch /etc/modules-load.d/k8s.conf"
    for mod in ${KERNEL_MODULES[@]}; do
        run_ssh_command $node "sudo modprobe $mod"
        run_ssh_command $node "echo $mod | sudo tee -a /etc/modules-load.d/k8s.conf"
    done

    ## Set sysctl Parameters
    run_ssh_command $node "sudo touch /etc/sysctl.d/99-k8s.conf"
    for sp in ${SYSCTL_PARAMS[@]}; do
        run_ssh_command $node "sudo sysctl -w $sp"
        run_ssh_command $node "echo $sp | sudo tee -a /etc/sysctl.d/99-k8s.conf"
    done
    run_ssh_command $node "sudo sysctl --system"

    # Install Docker
    node_arch=$(run_ssh_command $node 'dpkg --print-architecture')
    run_ssh_command $node "sudo install -m 0755 -d /etc/apt/keyrings"
    run_ssh_command $node "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    run_ssh_command $node "sudo chmod a+r /etc/apt/keyrings/docker.asc"
    run_ssh_command $node "echo 'Types: deb' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "echo 'URIs: https://download.docker.com/linux/ubuntu' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "echo 'Suites: noble' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "echo 'Components: stable' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "echo 'Architectures: $node_arch' | sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "echo 'Signed-By: /etc/apt/keyrings/docker.asc'| sudo tee -a /etc/apt/sources.list.d/docker.sources"
    run_ssh_command $node "sudo apt update"
    run_ssh_command $node "sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    run_ssh_command $node "sudo systemctl start docker"
    get_service_status "docker"
    run_ssh_command $node "sudo chmod 666 /etc/containerd/config.toml"
    run_ssh_command $node "sudo containerd config default > /etc/containerd/config.toml"
    run_ssh_command $node "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml"
    run_ssh_command $node "sudo chmod 644 /etc/containerd/config.toml"
    run_ssh_command $node "sudo systemctl restart containerd"
    get_service_status "containerd"

    # Install Kubernetes
    run_ssh_command $node "sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v${config[kube_version]}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    kube_package_string="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${config[kube_version]}/deb/ /"
    run_ssh_command $node "echo $kube_package_string | sudo tee -a /etc/apt/sources.list.d/kubernetes.list"
    run_ssh_command $node "sudo apt update"
    run_ssh_command $node "sudo apt install -y kubelet kubeadm kubectl"
    run_ssh_command $ndoe "sudo apt-mark hold kubelet kubeadm kubectl"
    run_ssh_command $node "sudo systemctl enable kubelet"
    run_ssh_command $node "sudo systemctl start kubelet"

    echo
done

# Controller node
## initialize control plane
run_ssh_command ${config[control_node]} "sudo kubeadm init --pod-network-cidr=${config[pod_network_cidr]} --service-cidr=${config[service_cidr]}"

## Enable User/Root Kube config
run_ssh_command ${config[control_node]} "sudo mkdir /root/.kube"
run_ssh_command ${config[control_node]} "sudo cp /etc/kubernetes/admin.conf /root/.kube/config"
run_ssh_command ${config[control_node]} "sudo chmod 755 /root/.kube"
run_ssh_command ${config[control_node]} "sudo chmod 600 /root/.kube"
run_ssh_command ${config[control_node]} "sudo mkdir /home/$USER/.kube"
run_ssh_command ${config[control_node]} "sudo cp /etc/kubernetes/admin.conf /home/$USER/.kube/config"
run_ssh_command ${config[control_node]} "sudo chown -R $USER:$USER /home/$USER/.kube"
run_ssh_command ${config[control_node]} "sudo chmod 755 /home/$USER/.kube"
run_ssh_command ${config[control_node]} "sudo chmod 600 /home/$USER/.kube/config"
kube_join_cmd=$(run_ssh_command ${config[control_node]} "sudo kubeadm token create --print-join-command")

## Install Calico CNI
tigera_url="https://raw.githubusercontent.com/projectcalico/calico/${config[calico_version]}/manifests/tigera-operator.yaml"
calico_url="https://raw.githubusercontent.com/projectcalico/calico/${config[calico_version]}/manifests/custom-resources.yaml"
pod_network_string=${config[pod_network_cidr]}
sed_network_string="${pod_network_string//./\\.}"
sed_network_string="${sed_network_string////\\/}"

run_ssh_command ${config[control_node]} "sudo kubectl create -f $tigera_url"
run_ssh_command ${config[control_node]} "sudo curl -fsSL $calico_url -o /tmp/calico-custom-resources.yaml"
run_ssh_command ${config[control_node]} "sudo chmod 664 /tmp/calico-custom-resources.yaml"
run_ssh_command ${config[control_node]} "sudo sed -i "s@192\.168\.0\.0\/16@$sed_network_string@g" /tmp/calico-custom-resources.yaml"
run_ssh_command ${config[control_node]} "sudo kubectl create -f /tmp/calico-custom-resources.yaml"
run_ssh_command ${config[control_node]} "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

## Wait for Calico to be ready
sleep 30
run_ssh_command ${config[control_node]} "kubectl wait --namespace calico-system --for=condition=ready pod --selector=k8s-app=calico-node --timeout=300s"

## Wait for control plane to be ready
cp_status=$(run_ssh_command ${config[control_node]} "kubectl get nodes | sed -n '2p'")
cp_status=$(echo $cp_status | awk '{print $2}')
printf "Waiting for Control Plane to be ready"
while [[ "$cp_status" != "Ready" ]]; do
    cp_status=$(run_ssh_command ${config[control_node]} "kubectl get nodes | sed -n '2p'")
    cp_status=$(echo $cp_status | awk '{print $2}')
    printf "."
    sleep 5
done
echo
echo "Control Plane: $cp_status"

## install local-path-provisioner for storage
run_ssh_command ${config[control_node]} "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml"
run_ssh_command ${config[control_node]} "kubectl patch storageclass local-path -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"

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

## Wait for workers to be ready
ready_node_count=$(run_ssh_command ${config[control_node]} 'kubectl get nodes | sed "1d" | awk "{print $2}" | grep Ready | wc -l')
worker_node_count=${#worker_node_array[@]}
node_count=$((worker_node_count + 1))
echo "$ready_node_count/$node_count nodes ready"
while [[ $ready_node_count !=  $node_count ]]; do
    echo "$ready_node_count/$node_count nodes ready"
    sleep 5
    ready_node_count=$(run_ssh_command ${config[control_node]} 'kubectl get nodes | sed "1d" | awk "{print $2}" | grep Ready | wc -l')
done

# Install Metallb
run_ssh_command ${config[control_node]} "sudo helm repo add metallb https://metallb.github.io/metallb"
run_ssh_command ${config[control_node]} "sudo helm repo update"
run_ssh_command ${config[control_node]} "sudo kubectl create namespace ${config[metallb_namespace]}"
run_ssh_command ${config[control_node]} "sudo helm install metallb metallb/metallb --namespace ${config[metallb_namespace]} --version ${config[metallb_version]} --wait"
run_ssh_command ${config[control_node]}  "kubectl wait --namespace ${config[metallb_namespace]} --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s"

## Create Metallb IP pool
run_ssh_command ${config[control_node]} "printf \"apiVersion: metallb.io/v1beta1\nkind: IPAddressPool\nmetadata:\n  name: ${config[metallb_pool_name]}\n  namespace: ${config[metallb_namespace]}\nspec:\n  addresses:\n    - ${config[metallb_pool_range]}\" | kubectl apply -f -"

## Create Metallb L2 adertisement
run_ssh_command ${config[control_node]} "printf \"apiVersion: metallb.io/v1beta1\nkind: L2Advertisement\nmetadata:\n  name: ${config[metallb_l2ad_name]}\n  namespace: ${config[metallb_namespace]}\nspec:\n  ipAddressPools:\n    - ${config[metallb_pool_name]}\" | kubectl apply -f -"

# Install Kgateway
## Install GatewayAPI CRDs
run_ssh_command ${config[control_node]} "kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${config[gateway_api_version]}/${config[gateway_api_stream]}-install.yaml"

## Install Kgateway
sftp_put ${config[control_node]} "./manifests/api-gateway.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/api-http-redirect.yaml" "/home/${config[ssh_user]}"
run_ssh_command ${config[control_node]} "kubectl create namespace kgateway-system"
run_ssh_command ${config[control_node]} "helm upgrade -i kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds --namespace kgateway-system --version ${config[kgateway_version]}"
run_ssh_command ${config[control_node]} "helm upgrade -i kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --namespace kgateway-system --version ${config[kgateway_version]} --set agentgateway.enabled=false --set controller.image.pullPolicy=Always --wait --timeout 5m"
run_ssh_command ${config[control_node]} "kubectl wait --namespace kgateway-system --for=condition=ready pod --selector=app.kubernetes.io/name=kgateway --timeout=300s"
run_ssh_command ${config[control_node]} "kubectl apply -f api-gateway.yaml"

# Install Cert Manager
run_ssh_command ${config[control_node]} "helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --version ${config[cert_manager_version]} --namespace cert-manager --create-namespace --set crds.enabled=true --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" --set config.kind="ControllerConfiguration" --set config.enableGatewayAPI=true"
run_ssh_command ${config[control_node]} "kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app=cert-manager --timeout=300s"

## Create Cluster Issuer/CA Cert
sftp_put ${config[control_node]} "./manifests/global-issuer.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/ca-cert.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/ca-issuer.yaml" "/home/${config[ssh_user]}"

run_ssh_command ${config[control_node]} "kubectl apply -f global-issuer.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f ca-cert.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f ca-issuer.yaml"

# Create app-deploy user and capture config
sftp_put ${config[control_node]} "./manifests/johnny-role.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/johnny-sa.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/johnny-rb.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/johnny-token.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/johnny-kgateway-read.yaml" "/home/${config[ssh_user]}"
sftp_put ${config[control_node]} "./manifests/johnny-kgateway-rb.yaml" "/home/${config[ssh_user]}"

run_ssh_command ${config[control_node]} "kubectl create namespace johnny-droptables"
run_ssh_command ${config[control_node]} "kubectl apply -f api-http-redirect.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-role.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-sa.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-rb.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-kgateway-read.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-kgateway-rb.yaml"
run_ssh_command ${config[control_node]} "kubectl apply -f johnny-token.yaml"

johnny_token=$(run_ssh_command ${config[control_node]} "kubectl get secret johnny-not-secure-token -n johnny-droptables -o jsonpath='{.data.token}' | base64 --decode")
kube_config="--kubeconfig=.kube/johnny.config"
run_ssh_command ${config[control_node]} "kubectl config $kube_config set-cluster kubernetes --server=https://${config[control_node]}:6443 --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true"
run_ssh_command ${config[control_node]} "kubectl config $kube_config set-credentials johnny-d-sa --token=$johnny_token"
run_ssh_command ${config[control_node]} "kubectl config $kube_config set-context johnny-d-sa-context --cluster=kubernetes --namespace=johnny-droptables --user=johnny-d-sa"
run_ssh_command ${config[control_node]} "kubectl config $kube_config use-context johnny-d-sa-context"
run_ssh_command ${config[control_node]} "chmod 600 .kube/johnny.config"

# "Lock" Johnny out of admin
run_ssh_command ${config[control_node]} "mv .kube/config .kube/config.bak"
run_ssh_command ${config[control_node]} "rm -f .kube/config"
run_ssh_command ${config[control_node]} "cp .kube/johnny.config .kube/config"

# Put helm chart on control-node
sftp_put ${config[control_node]} "..app-deploy/t-eval.gz" "/home/${config[ssh_user]}"