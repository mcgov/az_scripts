#! /bin/pwsh
param(
    [string] $ResourceGroupName = "dpdk-fwd-example-default",
    [string] $SshPublicKey,
    [string] $Region,
    [System.Collections.Hashtable] $AvSetTags = @{},
    [switch] $TryRunTest,
    [switch] $cleanupFailure
)

# az login
# az account set --subscription "Your Subscription Name"

# Create an environment to run the DPDK l3fwd sample application.
# The az cli commands should work across platforms if formatted correctly.
# This is a powershell file but theoretically would work on Linux if you installed powershell...
# It's untested. Will work on Windows.

$os_image = "canonical 0001-com-ubuntu-server-jammy 22_04-lts-gen2 latest"
$ResourceGroupName = $ResourceGroupName
$avname = "$ResourceGroupName-avset"
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
$subnet_b_route_a_em = $subnet_a_snd_ip + '/32'
$subnet_a_route_b_em = $subnet_b_rcv_ip + '/32'

$fwd_vm_name = "forward"
$snd_vm_name = "sender"
$rcv_vm_name = "receive"

# drop all traffic destined for subnet 0 on all subnets
$mgmt_first_hop = $subnet_0_prefix + '.0/24'
$a_first_hop = $subnet_a_prefix + '.0/24'
$b_first_hop = $subnet_b_prefix + '.0/24'

$vmSize = 'Standard_D32s_v3'

$fwd_build_disk = "data_disk_fwd"
$build_disk_dir = '/tmp/build'
$az_scripts_git = 'https://www.github.com/mcgov/az_scripts.git'


# helpers
function AssertSuccess([string] $ResourceGroupName){
    if (-not $?){
        if ($cleanupFailure){
            DeleteResources($ResourceGroupName);
        }
        throw "Last call failed! Check spew for details, exit code: $?";
    }
}
function DeleteResources([string] $ResourceGroupName){
    write-host "Deleting resource group $ResourceGroupName..."
    az group delete -g $ResourceGroupName -f 'Microsoft.Compute/virtualMachines' -y;
}

#AzCli likes the colon format instead of the space format for marketplace image names
function ForceMarketplaceUrnFormat([string] $imageName){
    return $imageName.replace(" ", ":")
}


# make our RG
Write-Host "Creating resource group $ResourceGroupName"
az group create --location $region --resource-group $ResourceGroupName; AssertSuccess($ResourceGroupName)
# Make our availability set
if ($AvSetTags) {
    write-host "Creating avset $avname"
    # az cli asks you to pass space seperated arguments sometimes which...
    # is weird to me.
    $tagArgs = @()
    foreach ($t in $AvSetTags.Keys){
        $TagArgs += @( "$t=" + $AvSetTags[$t] )
    }
    $tags = $TagArgs -join ' '
    write-host "attempting to apply tags: $tags"
    az vm availability-set create -n $avname -g $ResourceGroupName --platform-fault-domain-count 1 --platform-update-domain-count 1 --tags $tags;
    AssertSuccess($ResourceGroupName)
} else {
    write-host "No availability set tags provided, skipping availability set creation..."
}

# make our network and nsg
write-host "Creating vnet and NSG..."
az network vnet create --resource-group $ResourceGroupName --name $vnet; AssertSuccess($ResourceGroupName)
az network nsg create -n $nsg -g $ResourceGroupName -l westus3; AssertSuccess($ResourceGroupName) 
# create the routing tables, will fill out with rules to ban traffic
# jumping between subnets without going to forwarder VM first 
write-host "Creating routing tables..."
az network route-table create -n $route_0 -g $ResourceGroupName; AssertSuccess($ResourceGroupName)
az network route-table create -n $route_a -g $ResourceGroupName; AssertSuccess($ResourceGroupName)
az network route-table create -n $route_b -g $ResourceGroupName; AssertSuccess($ResourceGroupName)


# create the subnets 
write-host "Creating subnets..."
az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_0 --address-prefix '10.0.0.0/24' --network-security-group $nsg --route-table $route_0 ; AssertSuccess($ResourceGroupName)
az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_a --address-prefix '10.0.1.0/24' --network-security-group $nsg --route-table $route_a; AssertSuccess($ResourceGroupName)
az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_b  --address-prefix '10.0.2.0/24' --network-security-group $nsg --route-table $route_b; AssertSuccess($ResourceGroupName)

# create the NICs we'll use on our VMs and assign them to the subnets
write-host "Creating mgmt nics..."
foreach ($i in 0,1,2){
    $id = $i + 4; # Note: need to add some offset the ip addresses.
    $ip_address = $subnet_0_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n mgmt-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_0 --vnet-name $vnet; AssertSuccess($ResourceGroupName)
}
write-host "Creating client-side nics..."
foreach ($i in 0,1){
    $id = $i + 4; 
    $ip_address = $subnet_a_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n snd-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_a --vnet-name $vnet; AssertSuccess($ResourceGroupName)
}
# create the receiver nics as 0 , 2 to let the VM names match up w the subnets.
write-host "Creating server-side nics..."
foreach ($i in 0,2){
    $id = $i + 4;
    $ip_address = $subnet_b_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n rcv-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_b --vnet-name $vnet; AssertSuccess($ResourceGroupName)
}
write-host "Creating routing rules..."
# drop all traffic for mgmt subnet subnet_0
az network route-table route create -g $ResourceGroupName --name $subnet_0_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_0 ; AssertSuccess($ResourceGroupName)
az network route-table route create -g $ResourceGroupName --name $subnet_a_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_a; AssertSuccess($ResourceGroupName)
az network route-table route create -g $ResourceGroupName --name $subnet_b_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_b; AssertSuccess($ResourceGroupName)

# fwd traffic from b to a to fwder on a
az network route-table route create -g $ResourceGroupName --name $subnet_a_fwd --address-prefix $subnet_a_route_b_em --next-hop-type VirtualAppliance --route-table-name $route_a --next-hop-ip-address $subnet_a_fwd_ip; AssertSuccess($ResourceGroupName)

# fwd all traffic from a to b to fwder on b
az network route-table route create -g $ResourceGroupName --name $subnet_b_fwd --address-prefix $subnet_b_route_a_em --next-hop-type VirtualAppliance --route-table-name $route_b --next-hop-ip-address $subnet_b_fwd_ip; AssertSuccess($ResourceGroupName)

# drop all other traffic from a to b
az network route-table route create -g $ResourceGroupName --name $subnet_a_drop_b --address-prefix $b_first_hop --next-hop-type None --route-table-name $route_a ; AssertSuccess($ResourceGroupName)

# and all other traffic from b to a
az network route-table route create -g $ResourceGroupName --name $subnet_b_drop_a --address-prefix $a_first_hop --next-hop-type None --route-table-name $route_b; AssertSuccess($ResourceGroupName)

write-host "Creating VMs..."
# Create the VMs
$imageUrn = ForceMarketplaceUrnFormat($os_image)
# forwarder gets a nic on each subnet
write-host "Creating forwarder..."
$mgmtVm = az vm create -n $fwd_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-0 snd-nic-vm-0 rcv-nic-vm-0; AssertSuccess($ResourceGroupName)
# sender gets a mgmt nic and a nic on subnet a
write-host "Creating client..."
$sndVm = az vm create -n $snd_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-1 snd-nic-vm-1; AssertSuccess($ResourceGroupName)
# receiver gets a mgmt nic and a nic on subnet b
write-host "Creating server..."
$rcvVM = az vm create -n $rcv_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-2 rcv-nic-vm-2; AssertSuccess($ResourceGroupName)

# I don't use the results but I think this is a neat trick, feel free to investigate it more.
# pwsh json handling is great! Usually!
$mgmtVM = $mgmtVM | ConvertFrom-Json 
$rcvVM = $rcvVM | ConvertFrom-Json
$sndVM = $sndVM | ConvertFrom-Json

write-host "Setting up forwarder..."
# add a data disk to the fwder to compile rdma-core and dpdk
az vm disk attach -g $ResourceGroupName --vm-name $fwd_vm_name --name $fwd_build_disk --size-gb 128 --new; AssertSuccess($ResourceGroupName)

# make the data disk parition and mark it r/w
write-host "Formatting build data disk..."
# Warning: Ugly terrible code
$success = $false
foreach ($disk in "sdb","sdc"){
    $result = az vm run-command invoke --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "sudo mkfs.ext4 /dev/$disk && mkdir $build_disk_dir && sudo mount /dev/$disk $build_disk_dir && sudo chmod +rw $build_disk_dir; " ; AssertSuccess($ResourceGroupName)
    $message = ($result | ConvertFrom-Json).$message
    if ($message.contains("/dev/$disk already mounted or mount point busy")) {
        write-host "$disk was a bad choice... let's try again. "
    } else {
        $success = $true
        break;
    }
}
if (-not $success){
    write-error "Could not find the data disk after adding it. If you hit this error, complain to github.com/mcgov"
    write-host "bailing... leftover rg name is: $rg"
    exit -1;
}

# install setup stuff
write-host "Installing build tools on forwarder..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get upgrade -y -q && sudo apt-get install -y -q git build-essential python3-pip" ; AssertSuccess($ResourceGroupName)
write-host "Installing sockperf (client)..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $snd_vm_name  --command-id "RunShellScript" --script "export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get -y -q install sockperf"
write-host "Installing sockperf (server)..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $rcv_vm_name  --command-id "RunShellScript" --script "export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get -y -q install sockperf"

# clone the az scripts repo
write-host "Cloning az_scripts repo..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "git clone $az_scripts_git $build_disk_dir/az_scripts" ; AssertSuccess($ResourceGroupName)

# mark scripts executable and run the setup
write-host "Running DPDK installation..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "cd $build_disk_dir/az_scripts/dpdk-helpers; chmod +x ./*.sh; DEBIAN_FRONTEND=noninteractive ./dpdk-test-setup.ubuntu.sh" ; AssertSuccess($ResourceGroupName)

if (-not $TryRunTest){ 
    return 0;
}
# make the l3fwd rules files. NOTE: not sure this works as expected yet.
write-host "Creating l3fwd rules files..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; chmod +x ./*.sh; ./create_l3fwd_rules_files.sh $a_first_hop $b_first_hop" ; AssertSuccess($ResourceGroupName)

# start the forwarder
write-host "Running DPDK l3fwd (async)..."
az vm run-command invoke --no-wait --resource-group $ResourceGroupName  -n $fwd_vm_name --command-id "RunShellScript" --script "cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; ./run-dpdk-l3fwd.sh $build_disk_dir/az_scripts/dpdk-helpers/dpdk/build/examples/dpdk-l3fwd";
# start the receiver
write-host "Starting server (async)..."
az vm run-command invoke --no-wait --resource-group $ResourceGroupName  -n $rcv_vm_name  --command-id "RunShellScript" --script "sudo timeout 1200 sockperf server --tcp -i $subnet_b_rcv_ip";
# start the sender
write-host "Starting client..."
az vm run-command invoke --resource-group $ResourceGroupName  -n $snd_vm_name  --command-id "RunShellScript" --script "sudo sockperf ping-pong --tcp --full-rtt -i $subnet_b_rcv_ip"

write-host "Stopping forwarder and server.."
get-job | stop-job

# NOTE: add tip stuff and availability set option

# az group delete -g $ResourceGroupName ; # answer yes