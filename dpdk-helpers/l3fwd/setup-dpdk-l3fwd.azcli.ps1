#! /bin/pwsh
param(
    [string] $ResourceGroupName = 'dpdk-fwd-example-default',
    [string] $SshPublicKey,
    [string] $Region,
    [System.Collections.Hashtable] $AvSetTags = $null,
    [string] $AvSetProperties = "",
    [string] $avSetPropertyName = "",
    [switch] $TryRunTest,
    [switch] $cleanupFailure,
    [switch] $cleanupSuccess
)

# NOTE: script assumes you have set up your environment. Make sure to login before you run the script, otherwise the default subscription might be different than you expect!

# az login
# az account set --subscription "Your Subscription Name"

# Create an environment to run the DPDK l3fwd sample application.
# The az cli commands should work across platforms if formatted correctly.
# This is a powershell file but theoretically would work on Linux if you installed powershell...
# It's untested. Will work on Windows.

$os_image = 'canonical 0001-com-ubuntu-server-jammy 22_04-lts-gen2 latest'
$ResourceGroupName = $ResourceGroupName
$avname = "$ResourceGroupName-avset"
$vnet = 'test-vnet'
$nsg = 'test-nsg'; 
$route_0 = 'route-0'; # mgmt network
$route_a = 'route-a'; 
$route_b = 'route-b'; 
$subnet_a = 'subnet-0'
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

$fwd_vm_name = 'forward'
$snd_vm_name = 'sender'
$rcv_vm_name = 'receive'

# drop all traffic destined for subnet 0 on all subnets
$mgmt_first_hop = $subnet_0_prefix + '.0/24'
$a_first_hop = $subnet_a_prefix + '.0/24'
$b_first_hop = $subnet_b_prefix + '.0/24'

$vmSize = 'Standard_D32s_v3'

$fwd_build_disk = 'data_disk_fwd'
$build_disk_dir = '/tmp/build'
$az_scripts_git = 'https://www.github.com/mcgov/az_scripts.git'


# helpers
function AssertSuccess([string] $ResourceGroupName) {
    if (-not $?) {
        if ($cleanupFailure) {
            DeleteResources($ResourceGroupName);
        }
        throw "Last call failed! Check spew for details, exit code: $?";
    }
}
function DeleteResources([string] $ResourceGroupName) {
    Write-Host "Deleting resource group $ResourceGroupName..."
    az group delete -g $ResourceGroupName -f 'Microsoft.Compute/virtualMachines' -y;
}

#AzCli likes the colon format instead of the space format for marketplace image names
function ForceMarketplaceUrnFormat([string] $imageName) {
    return $imageName.replace(' ', ':')
}

function map_ipv4_to_ipv6([string]$ipv4){
    $ipv6 = "0000:0000:0000:0000:0000:FFFF:"
    # split ipv4 address 
    $split_ipv4 = $ipv4.split('.')
    # apply hex to the first two digits
    foreach($digit in $split_ipv4[0..1]) {
         $ipv6 += "{0:x2}" -f ([int]$digit); 
    }
    # add the third digit, we're making a mask
    # so discard the fourth to make a /56
    $ipv6 += ":"
    # return a /56 lpm ipv6 mapped ipv4 address
    $ipv6 += "{0:x2}00/56" -f ([int]$split_ipv4[2]);
    write-host "Mapped $ipv4 to $ipv6..." 
    return $ipv6
}
# make our RG
Write-Host "Creating resource group $ResourceGroupName"
az group create --location $region --resource-group $ResourceGroupName
AssertSuccess($ResourceGroupName)
# Make our availability set
if ($AvSetTags) {
    Write-Host "Creating avset $avname"
    # az cli asks you to pass space seperated arguments sometimes which...
    # is weird to me.
    
    if ($AvSetTags.Count -gt 0 ) {
        Write-Host "attempting to apply av set updates..."
        az vm availability-set create -n $avname -g $ResourceGroupName --platform-fault-domain-count 1 --platform-update-domain-count 1;
        AssertSuccess($ResourceGroupName)
        if ($AvSetProperties -and $avSetPropertyName){
            az vm availability-set update --add property.$AvSetPropertyName $AvSetProperties 
            AssertSuccess($ResourceGroupName)

        } 
        foreach ($t in $AvSetTags.Keys) {
            az vm availability-set update -add tags.$t=$AvSetTags[$t]
            AssertSuccess($ResourceGroupName)
        }
    }
}
else {
    Write-Host 'No availability set tags provided, skipping availability set creation...'
}

# make our network and nsg
Write-Host 'Creating vnet and NSG...'
az network vnet create --resource-group $ResourceGroupName --name $vnet
AssertSuccess($ResourceGroupName)

az network nsg create -n $nsg -g $ResourceGroupName -l westus3
AssertSuccess($ResourceGroupName) 

# create the routing tables, will fill out with rules to ban traffic
# jumping between subnets without going to forwarder VM first 
Write-Host 'Creating routing tables...'
az network route-table create -n $route_0 -g $ResourceGroupName
AssertSuccess($ResourceGroupName)

az network route-table create -n $route_a -g $ResourceGroupName
AssertSuccess($ResourceGroupName)

az network route-table create -n $route_b -g $ResourceGroupName
AssertSuccess($ResourceGroupName)


# create the subnets 
Write-Host 'Creating subnets...'
az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_0 --address-prefix '10.0.0.0/24' --network-security-group $nsg --route-table $route_0 
AssertSuccess($ResourceGroupName)

az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_a --address-prefix '10.0.1.0/24' --network-security-group $nsg --route-table $route_a
AssertSuccess($ResourceGroupName)

az network vnet subnet create --resource-group $ResourceGroupName --vnet-name test-vnet -n $subnet_b --address-prefix '10.0.2.0/24' --network-security-group $nsg --route-table $route_b
AssertSuccess($ResourceGroupName)

# create the NICs we'll use on our VMs and assign them to the subnets
write-host "Creating public ips for mgmt nics"
foreach ($i in 0,1,2) {
    az network public-ip create -g $ResourceGroupName -n "mgmt-public-ip-$i"
    AssertSuccess($ResourceGroupName)
}

Write-Host 'Creating mgmt nics...'

foreach ($i in 0, 1, 2) {
    $id = $i + 4; # Note: need to add some offset the ip addresses.
    $ip_address = $subnet_0_prefix + '.' + $id
    az network nic create --private-ip-address $ip_address -n mgmt-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_0 --vnet-name $vnet --public-ip-address "mgmt-public-ip-$i"
    AssertSuccess($ResourceGroupName)
}
Write-Host 'Creating client-side nics...'
foreach ($i in 0, 1) {
    $id = $i + 4; 
    $ip_address = $subnet_a_prefix + '.' + $id
    # enable ip forwarding for fwder nics
    if ($i -eq 0){
        $ip_forward = 1
    } else {
        $ip_forward = 0
    }
    az network nic create --private-ip-address $ip_address -n snd-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_a --vnet-name $vnet --ip-forwarding $ip_forward
    AssertSuccess($ResourceGroupName)
}
# create the receiver nics as 0 , 2 to let the VM names match up w the subnets.
Write-Host 'Creating server-side nics...'
foreach ($i in 0, 2) {
    $id = $i + 4;
    $ip_address = $subnet_b_prefix + '.' + $id
    # enable ip forwarding for fwder nics
    if ($i -eq 0) {
        $ip_forward = 1
    } else {
        $ip_forward = 0
    }
    az network nic create --private-ip-address $ip_address -n rcv-nic-vm-$i -g $ResourceGroupName --accelerated-networking 1 --subnet $subnet_b --vnet-name $vnet --ip-forwarding $ip_forward
    AssertSuccess($ResourceGroupName)
}
Write-Host 'Creating routing rules...'
# drop all traffic for mgmt subnet subnet_0
az network route-table route create -g $ResourceGroupName --name $subnet_0_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_0 
AssertSuccess($ResourceGroupName)

az network route-table route create -g $ResourceGroupName --name $subnet_a_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_a
AssertSuccess($ResourceGroupName)

az network route-table route create -g $ResourceGroupName --name $subnet_b_drop_0 --address-prefix $mgmt_first_hop --next-hop-type None --route-table-name $route_b
AssertSuccess($ResourceGroupName)

# fwd traffic from b to a to fwder on a
az network route-table route create -g $ResourceGroupName --name $subnet_a_fwd --address-prefix $subnet_a_route_b_em --next-hop-type VirtualAppliance --route-table-name $route_a --next-hop-ip-address $subnet_a_fwd_ip
AssertSuccess($ResourceGroupName)

# fwd all traffic from a to b to fwder on b
az network route-table route create -g $ResourceGroupName --name $subnet_b_fwd --address-prefix $subnet_b_route_a_em --next-hop-type VirtualAppliance --route-table-name $route_b --next-hop-ip-address $subnet_b_fwd_ip
AssertSuccess($ResourceGroupName)

# drop all other traffic from a to b
az network route-table route create -g $ResourceGroupName --name $subnet_a_drop_b --address-prefix $b_first_hop --next-hop-type None --route-table-name $route_a 
AssertSuccess($ResourceGroupName)

# and all other traffic from b to a
az network route-table route create -g $ResourceGroupName --name $subnet_b_drop_a --address-prefix $a_first_hop --next-hop-type None --route-table-name $route_b
AssertSuccess($ResourceGroupName)

Write-Host 'Creating VMs...'
# Create the VMs
$imageUrn = ForceMarketplaceUrnFormat($os_image)

# forwarder gets a nic on each subnet
Write-Host 'Creating forwarder...'
$mgmtVm = az vm create -n $fwd_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-0 snd-nic-vm-0 rcv-nic-vm-0
AssertSuccess($ResourceGroupName)
Write-Host $mgmtVm

# sender gets a mgmt nic and a nic on subnet a
Write-Host 'Creating client...'
$sndVm = az vm create -n $snd_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-1 snd-nic-vm-1
AssertSuccess($ResourceGroupName)
Write-Host $sndVm

# receiver gets a mgmt nic and a nic on subnet b
Write-Host 'Creating server...'
$rcvVM = az vm create -n $rcv_vm_name -g $ResourceGroupName --size $vmSize --image $imageUrn --ssh-key-values "$SshPublicKey" --nics mgmt-nic-vm-2 rcv-nic-vm-2
AssertSuccess($ResourceGroupName)
Write-Host $rcvVm

# I don't use the results but I think this is a neat trick, feel free to investigate it more.
# pwsh json handling is great! Usually!
$mgmtVM = $mgmtVM | ConvertFrom-Json 
$rcvVM = $rcvVM | ConvertFrom-Json
$sndVM = $sndVM | ConvertFrom-Json

Write-Host 'Setting up forwarder...'
# add a data disk to the fwder to compile rdma-core and dpdk
az vm disk attach -g $ResourceGroupName --vm-name $fwd_vm_name --name $fwd_build_disk --size-gb 128 --new
AssertSuccess($ResourceGroupName)

# make the data disk parition and mark it r/w
Write-Host 'Formatting build data disk...'
# Warning: Ugly terrible code
$success = $false
foreach ($disk in 'sdb', 'sdc') {
    Write-Host "checking /dev/$disk..."
    $result = az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "sudo mkfs.ext4 /dev/$disk && mkdir $build_disk_dir && sudo mount /dev/$disk $build_disk_dir && sudo chmod +rw $build_disk_dir; ";
    AssertSuccess($ResourceGroupName)
    if (-not $result) {
        Write-Error "unexplained lack of output... hmm... rg name was $ResourceGroupName"
        exit -1
    }
    $message = ($result | ConvertFrom-Json).value.message
    if ($message.contains("/dev/$disk already mounted or mount point busy")) {
        Write-Host "$disk was a bad choice... let's try again. "
    }
    else {
        $success = $true
        break;
    }
}
if (-not $success) {
    Write-Error 'Could not find the data disk after adding it. If you hit this error, complain to github.com/mcgov'
    Write-Host "bailing... leftover rg name is: $ResourceGroupName"
    exit -1;
}

# install setup stuff
Write-Host 'Installing build tools on forwarder...'
az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get upgrade -y -q && sudo apt-get install -y -q git build-essential python3-pip' 
AssertSuccess($ResourceGroupName)
Write-Host 'Installing sockperf (client)...'
az vm run-command invoke --resource-group $ResourceGroupName -n $snd_vm_name --command-id 'RunShellScript' --script 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get -y -q install sockperf'
Write-Host 'Installing sockperf (server)...'
az vm run-command invoke --resource-group $ResourceGroupName -n $rcv_vm_name --command-id 'RunShellScript' --script 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -y -q && sudo apt-get -y -q install sockperf'

# clone the az scripts repo
Write-Host 'Cloning az_scripts repo...'
az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "git clone $az_scripts_git $build_disk_dir/az_scripts" 
AssertSuccess($ResourceGroupName)

# mark scripts executable and run the setup
Write-Host 'Running DPDK installation...'
az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "cd $build_disk_dir/az_scripts/dpdk-helpers; DEBIAN_FRONTEND=noninteractive ./run-dpdk-test-setup.ubuntu.sh" 
AssertSuccess($ResourceGroupName)

if (-not $TryRunTest) { 
    return 0;
}

# make the l3fwd rules files. NOTE: not sure this works as expected yet.
Write-Host 'Creating l3fwd rules files...'
az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; ./create_l3fwd_rules_files.sh $subnet_a_snd_ip $subnet_b_rcv_ip rules_ipv4 $build_disk_dir/az_scripts/dpdk-helpers/dpdk" 
AssertSuccess($ResourceGroupName)

# write ipv4 ips mapped t ipv6 for the v6 rules
$ipv6_sender = map_ipv4_to_ipv6($subnet_a_snd_ip)
$ipv6_receiver = map_ipv4_to_ipv6($subnet_b_rcv_ip)
az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; ./create_l3fwd_rules_files.sh $ipv6_sender $ipv6_receiver rules_ipv6 $build_disk_dir/az_scripts/dpdk-helpers/dpdk" 

az vm run-command invoke --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "ls $build_disk_dir/az_scripts/dpdk-helpers; ls $build_disk_dir/az_scripts/dpdk-helpers/dpdk/build/examples/";

# start the forwarder
Write-Host 'Running DPDK l3fwd (async)...'
az vm run-command invoke --no-wait --resource-group $ResourceGroupName -n $fwd_vm_name --command-id 'RunShellScript' --script "cd $build_disk_dir/az_scripts/dpdk-helpers/l3fwd; ./run-dpdk-l3fwd.sh $build_disk_dir/az_scripts/dpdk-helpers/dpdk/build/examples";

# start the receiver
#write-host "Starting server (async)..."
#az vm run-command invoke --no-wait --resource-group $ResourceGroupName  -n $rcv_vm_name  --command-id "RunShellScript" --script "sudo timeout 1200 sockperf server --tcp -i $subnet_b_rcv_ip";
# start the sender
#write-host "Starting client..."
#az vm run-command invoke --resource-group $ResourceGroupName  -n $snd_vm_name  --command-id "RunShellScript" --script "sudo sockperf ping-pong --tcp --full-rtt -i $subnet_b_rcv_ip"


Write-Host 'Starting server ping...'
az vm run-command invoke --resource-group $ResourceGroupName -n $rcv_vm_name --command-id 'RunShellScript' --script "timeout 30 ping  $subnet_a_snd_ip";


# start the sender
Write-Host 'Starting client ping...'
az vm run-command invoke --resource-group $ResourceGroupName -n $snd_vm_name --command-id 'RunShellScript' --script "timeout 30 ping $subnet_b_rcv_ip"

write-host "Writing send/receive ip's into files on receiver/sender..."
az vm run-command invoke --resource-group $ResourceGroupName -n $rcv_vm_name --command-id 'RunShellScript' --script "echo $subnet_a_snd_ip > ./sender_info  ";
az vm run-command invoke --resource-group $ResourceGroupName -n $snd_vm_name --command-id 'RunShellScript' --script "echo $subnet_b_snd_ip > ./receiver_info  ";

Write-Host 'Stopping forwarder and server..'
Get-Job | Stop-Job

# NOTE: add tip stuff and availability set option

if ($CleanupSuccess) {
    az group delete -y -g $ResourceGroupName ; # answer yes
}

