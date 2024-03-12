# Usage:
# first call `connect-azaccount` and login to your msft azure account
# then call 
# set-azcontext 'subscription id'
# where the id can be the name or guid
# I save the lsg dev and test one in my environment so it's just $env:lsgsub

# when calling this function:
# provide a VM family name (or substring of a family name) 
#  ex: DSv5, EADSv5, Boost, etc
# and the amount of cores you need. It will check quotas in different regions 
# and report which ones have space

# there is surely a way to do this with az-cli on linux, I haven't done it yet.
# I'll leave it as an exercise for the reader :P

function Find-AzSkuQuota([string] $sku, [int] $need_cores){
    $locations = 'eastus','eastus2','westus','centralus','northcentralus','southcentralus','northeurope','westeurope','eastasia','southeastasia','japaneast','japanwest','australiaeast','australiasoutheast','australiacentral','brazilsouth','southindia','centralindia','westindia','canadacentral','canadaeast','westus2','westcentralus','uksouth','ukwest','koreacentral','koreasouth','francecentral','southafricanorth','uaenorth','switzerlandnorth','germanywestcentral','norwayeast','jioindiawest','westus3','swedencentral','qatarcentral','polandcentral','italynorth','israelcentral','eastus2euap','centraluseuap'
    foreach ($region in $locations){
        write-debug "Checking $region..."
        $usage = Get-AzVmUsage -Location $region | Where-Object { $_.Name.Value -match $sku }
        if (-not $usage){ continue }
        if ($usage.Length -gt 1 ){
            Write-Host "Selector is not specific enough..."
            $usage | ConvertTo-Json | write-host
            return;
        }
        $limit = $usage.Limit
        $Current = $usage.CurrentValue
        $available = $limit - $current
        write-debug "Limit: $limit Current:$current Available:$available"
        if ( $available -ge $need_cores){
            Write-Host $region has $available cores of $Usage.Name.Value
        }
    }
}




