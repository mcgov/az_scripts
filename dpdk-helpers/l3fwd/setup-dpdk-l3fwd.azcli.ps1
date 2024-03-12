#! /bin/pwsh
param(
    [string] $SshPublicKey,
    [System.Collections.Hashtable] $AvSetTags = @{}
)

# az login
# az account set --subscription "Your Subscription Name"

# Create an environment to run the DPDK l3fwd sample application.
# The az cli commands should work across platforms if formatted correctly.
# This is a powershell file but theoretically would work on Linux if you installed powershell...
# It's untested. Will work on Windows.

$os_image = "canonical 0001-com-ubuntu-server-jammy 22_04-lts-gen2 latest"
$rgname = 'mcgov-fwd-example'
$avname = "$rgname-avset"
$region = 'westus3'
$username = "azureuser"
$vnet = 'test-vnet'
$nsg = 'test-nsg'; 
$route_0 = 'route-0'; # mgmt network
$route_a = 'route-a'; 
$route_b = 'route-b'; 
$subnet_a = "subnet-0"
$subnet_b = 'subnet-a'
$subnet_0 = 'subnet-b'

# we'll make a couple of rules for each route table:
# - drop all traffic for subnet 0 on all subnets
$subnet_0_drop_0 = 'subnet-0-drop-0'
$subnet_a_drop_0 = 'subnet-a-drop-0'
$subnet_b_drop_0 = 'subnet-b-drop-0'

# - route all traffic to forwarder
$subnet_a_fwd = 'subnet-a-fwd'
$subnet_b_fwd = 'subnet-b-fwd'

# - and drop all other traffic for b from a and a from b
$subnet_a_drop_b = 'subnet-a-drop-b'
$subnet_b_drop_a = 'subnet-b-drop-a'
# NOTE: private ip and nic numbering doesn't match up. 
# I'm naming the nics based on the VM number, we'll create routing rules later. 
# The IP addresses aren't that important as long as each subnet gets a 10.0.XX.0/24 range.

$subnet_0_prefix = '10.0.0'
$subnet_a_prefix = '10.0.1'
$subnet_b_prefix = '10.0.2'

# the fwder ip will always be x.x.x.4 in this example.
# it's arbitrary, could be whatever.
# sender is 10.0.1.5
# receiver is 10.0.2.6
$subnet_a_fwd_ip = $subnet_a_prefix + '.4'
$subnet_b_fwd_ip = $subnet_b_prefix + '.4'
$subnet_a_snd_ip = $subnet_a_prefix + '.5'
$subnet_b_rcv_ip = $subnet_b_prefix + '.6'
$subnet_b_dest_a_ip_prefix = $subnet_a_snd_ip + '/32'
$subnet_a_dest_b_ip_prefix = $subnet_b_rcv_ip + '/32'

$fwd_vm_name = "forward"
$snd_vm_name = "sender"
$rcv_vm_name = "receive"

$subnet_a_route = 'send-route'
$subnet_b_route = 'rcv-route'
$subnet_0_route = 'mgmt-route'

# drop all traffic destined for subnet 0 on all subnets
$mgmt_first_hop = $subnet_0_prefix + '.0/24'
$a_first_hop = $subnet_a_prefix + '.0/24'
$b_first_hop = $subnet_b_prefix + '.0/24'

$vmSize = 'Standard_D32s_v3'

$fwd_build_disk = "data_disk_fwd"
$build_disk_dir = '/tmp/build'
$fwd_build_disk = '/dev/sdc' # don't have a good system for getting this automatically.
$az_scripts_git = 'https://www.github.com/mcgov/az_scripts.git'


# helpers
function AssertSuccess(){
    if (-not $?){
        throw "Last call failed! Check output spew for errors."
        exit $?;
    }
}
function DeleteResources([string] $rgname){
    az group delete -g $rgname -f Microsoft.Compute/virtualMachines -y; AssertSuccess
}

#AzCli likes the colon format instead of the space format for marketplace image names
function ForceMarketplaceUrnFormat([string] $imageName){
    return $imageName.replace(" ", ":")
}


# make our RG
az group create --location $region --resource-group $rgname; AssertSuccess
# Make our availability set
az vm availability-set create -n $avname -g $rgname --platform-fault-domain-count 1 --platform-update-domain-count 1 --tags @AvSetTags

# make our network and nsg
az network vnet create --resource-group $rgname --name $vnet; AssertSuccess
az network nsg create -n $nsg -g $rgname -l westus3; AssertSuccess

# create the routing tables, will fill out with rules to ban traffic
# jumping between subnets without going to forwarder VM first 
az network route-table create -n $route_0 -g $rgname; AssertSuccess
az network route-table create -n $route_a -g $rgname; AssertSuccess
az network route-table create -n $route_b -g $rgname; AssertSuccess

# create the subnets 
az network vnet subnet create --resource-group $rgname --vnet-name test-vnet -n $subnet_0 --address-prefix '10.0.0.0/24' --network-security-group $nsg --route-table $route_0 ; AssertSuccess
az network vnet subnet create --resource-group $rgname --vnet-name test-vnet -n $subnet_a --address-prefix '10.0.1.0/24' --network-security-group $nsg --route-table $route_a; AssertSuccess
az network vnet subnet create --resource-group $rgname --vnet-name test-vnet -n $subnet_b  --address-prefix '10.0.2.0/24' --network-security-group $nsg --route-table $route_b; AssertSuccess

# create the NICs we'll use on our VMs and assign them to the subnets

foreach ($i in 0,1,2){
    $id = $i + 4; # Note: need to add some offset the ip addresses.
    $ip_address = $subnet_0_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n mgmt-nic-vm-$i -g $rgname --accelerated-networking 1 --subnet $subnet_0 --vnet-name $vnet; AssertSuccess
}
foreach ($i in 0,1){
    $id = $i + 4; 
    $ip_address = $subnet_a_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n snd-nic-vm-$i -g $rgname --accelerated-networking 1 --subnet $subnet_a --vnet-name $vnet; AssertSuccess
}
# create the receiver nics as 0 , 2 to let the VM names match up w the subnets.
foreach ($i in 0,2){
    $id = $i + 4;
    $ip_address = $subnet_b_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n rcv-nic-vm-$i -g $rgname --accelerated-networking 1 --subnet $subnet_b --vnet-name $vnet; AssertSuccess
}

# drop all traffic for mgmt subnet subnet_0
az network route-table route create -g $rgname --name $subnet_0_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_0 ; AssertSuccess
az network route-table route create -g $rgname --name $subnet_a_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_a; AssertSuccess
az network route-table route create -g $rgname --name $subnet_b_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_b; AssertSuccess

# fwd traffic from b to a to fwder on a
az network route-table route create -g $rgname --name $subnet_a_fwd --address-prefix $subnet_b_dest_a_ip_prefix --next-hop-type VirtualAppliance --route-table-name $route_a --next-hop-ip-address $subnet_a_fwd_ip; AssertSuccess

# fwd all traffic from a to b to fwder on b
az network route-table route create -g $rgname --name $subnet_a_fwd --address-prefix $subnet_b_dest_a_ip_prefix --next-hop-type VirtualAppliance --route-table-name $route_b --next-hop-ip-address $subnet_b_fwd_ip; AssertSuccess

# drop all other traffic from a to b
az network route-table route create -g $rgname --name $subnet_a_drop_b --address-prefix $b_first_hop --next-hop-type None --route-table-name $route_a ; AssertSuccess

# and all other traffic from b to a
az network route-table route create -g $rgname --name $subnet_b_drop_a --address-prefix $a_first_hop --next-hop-type None --route-table-name $route_b; AssertSuccess

# Create the VMs
$imageUrn = ForceMarketplaceUrnFormat($image)
# forwarder gets a nic on each subnet
$mgmtVm = az vm create -n $fwd_vm_name -g $rgname --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-0 snd-nic-vm-0 rcv-nic-vm-0; AssertSuccess
# sender gets a mgmt nic and a nic on subnet a
$sndVm = az vm create -n $snd_vm_name -g $rgname --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-1 snd-nic-vm-1; AssertSuccess
# receiver gets a mgmt nic and a nic on subnet b
$rcvVM = az vm create -n $rcv_vm_name -g $rgname --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-2 rcv-nic-vm-2; AssertSuccess

# I don't use the results but I think this is a neat trick, feel free to investigate it more.
# pwsh json handling is great! Usually!
$mgmtVM = $mgmtVM | ConvertFrom-Json 
$rcvVM = $rcvVM | ConvertFrom-Json
$sndVM = $sndVM | ConvertFrom-Json

# add a data disk to the fwder to compile rdma-core and dpdk
az vm disk attach -g $rgname --vm-name $fwd_vm_name --name $fwd_build_disk --size-gb 128 --new
# make the data disk parition and mark it r/w
az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "sudo mkfs.ext4 /dev/sdc; mkdir /tmp/build; sudo mount /dev/sdc /tmp/build; sudo chmod +rw /tmp/build; " ; AssertSuccess

# install setup stuff
az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive sudo apt-get update -y -q && DEBIAN_FRONTEND=noninteractive sudo apt-get upgrade -y -q && DEBIAN_FRONTEND=noninteractive sudo apt-get install -y -q git build-essential python3-pip" ; AssertSuccess

az vm run-command invoke --resource-group $rgname  -n $snd_vm_name  --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive sudo apt-get update -y -q && DEBIAN_FRONTEND=noninteractive sudo apt-get -y -q install sockperf"

az vm run-command invoke --resource-group $rgname  -n $rcv_vm_name  --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive sudo apt-get update -y -q && DEBIAN_FRONTEND=noninteractive sudo apt-get -y -q install sockperf"

# clone the az scripts repo
az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive git clone $az_scripts_git $build_disk_dir/az_scripts" ; AssertSuccess


# mark scripts executable and run the setup
az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive cd $build_disk_dir/az_scripts/dpdk-helpers; chmod +x ./*.sh; ./dpdk-test-setup.ubuntu.sh" ; AssertSuccess
# make the l3fwd rules files. NOTE: not sure this works as expected yet.
az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; chmod +x ./*.sh; ./create_l3fwd_rules_files.sh $a_first_hop $b_first_hop" ; AssertSuccess
# start the forwarder
$l3fwd_job = start-job -ScriptBlock { az vm run-command invoke --resource-group $rgname  -n $fwd_vm_name --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; ./run-dpdk-l3fwd.sh $build_disk_dir/az_scripts/dpdk-helpers/dpdk/build/examples/dpdk-l3fwd" ; }
# start the receiver
$recevier_job = start-job -ScriptBlock { az vm run-command invoke --resource-group $rgname  -n $rcv_vm_name  --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive sudo timeout 1200 sockperf server --tcp -i $subnet_b_rcv_ip" }
# start the sender
az vm run-command invoke --resource-group $rgname  -n $snd_vm_name  --command-id "RunShellScript" --script "DEBIAN_FRONTEND=noninteractive sudo sockperf ping-pong --tcp --full-rtt -i $subnet_b_rcv_ip"

get-job | stop-job

# NOTE: add tip stuff and availability set option

# az group delete -g $rgname ; # answer yes