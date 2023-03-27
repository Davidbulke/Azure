# Powershell script for Azure Arc Bridge deployment to Azure Stack HCI with Azure Stack HCI #
-----------------------------------------------------------------------------------------------
# Assuming the app is running as a containerised application.

# Azure Kubernetes Service (AKS) on Azure Stack HCI and Windows Server is an on-premises Kubernetes implementation of AKS.
# AKS on Azure Stack HCI and Windows Server automates running containerized applications at scale.
# AKS makes it quicker to get started hosting Linux and Windows containers in your datacenter.








#### S1: Dependancy installation required for Powershell modules. ####
#START---
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -Force
Install-Module -Name PowershellGet -Force -Confirm:$false -SkipPublisherCheck
exit
#END---
# New powershell module is required to start so that it loads the most up to date PowershellGet module.



############################################# S2: Installing the Azure Kubernetes Service.  ###################################################################################################################
#START---
& {
    Install-Module -Name AksHci -Repository PSGallery -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense
    Get-Command -Module AksHci
}
#END---



############################################# S3: Azure login for selectring the right subscription + registering the resource provider. ######################################################################

# Will need to copy and paste the code thats provided by powershell into the browser, so the AKS is registered to Azure.
#START---
& {
    # Connecting to Azure
    Connect-AzAccount -UseDeviceAuthentication
    # Selecting subscription
    $sub = Get-Option "Get-AzSubscription" "Name" # alternatively you can choose "SubscriptionID" if you a
    Set-AzContext $sub
    # Resource provider registering
    Register-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
    Register-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
}
#END---



############################################# S4: AKS installation preparation. ##########################################################################################################################################
#START---
& {
    $VerbosePreference = "Continue"
    Initialize-AksHciNode # !!!!!!!!! IMPORTANT: <- RUN THIS ON EVERY NODE!!!!!!!!!! (Checks if Windows remoting is enabled on the node)
}
# ---------------AFTER THE INITLISATION COMMAND RUN S1 TO S3 snippets---------------------


# Afterwards, next step is to configure AKS - so it knows about the Hyper-V switch that will be used. This needs to be done because it needs to know which switch to use.

###= This script snippet is setting up variables and configurations for deploying an Azure Kubernetes Service (AKS) cluster on Azure Stack HCI.

#### (A): Selecting Hyper-V VM switch for K8s VMs. ####
#==# The snippet below is being used to define the configuration settings for the virtual network that will be used by the AKS deployment. #==#

#START---
& {
    $vSwitchName = Get-Option "Get-VMSwitch" "NameOfTheSwitch"
    # Would need input - select the switch which can communicate with the Internet because it needs to download things from the internet & register to Azure.
}


#### (B): Configuration of variable file #################################################################################################################################################################################
#K8s node networking pools
& {
    $k8sNodeIpPoolStart = "192.168.177.2"   # Kubernetes node VM IP pool - used to allocate IP addresses to Kubernetes nodes virtual machines to enable communication between Kubernetes nodes
    $k8sNodeIpPoolEnd = "192.168.177.3"    # Will limit the number of Kubernetes nodes you can use
    $vipPoolStart = "192.168.177.21"        # Virtual IP pool - used to allocate IP addresses to the Kubernetes cluster API server.
    $vipPoolEnd = "192.168.177.22"
}

& {
$ipAddressPrefix = "192.168.177.0/24"
$gateway = "192.168.177.1"        # your router to get to the internet gateway
$dnsServers = "192.168.177.200"   # this is a domain controller (with DNS) role - as a computer object is created in AD -> you can precreate this in AD and specify it in  'Set-AksHciConfig'
$cloudservicecidr = "192.168.177.203/24"  # a free IP to be assigned for the clustered generic service that will be created and used. (Must be an free IP)
$csv_path = "c:\clusterstorage\cvs1"
}

#### (C): Static IP - Setting variables for config file + validation - this is for the AKS HCI module.
&{
    $vnet = New-AksHciNetworkSetting -name myaksnetwork -vSwitchName $vSwitchName `
  -k8sNodeIpPoolStart $k8sNodeIpPoolStart `
  -k8sNodeIpPoolEnd $k8sNodeIpPoolEnd `
  -vipPoolStart $vipPoolStart `
  -vipPoolEnd $vipPoolEnd `
  -ipAddressPrefix $ipAddressPrefix `
  -gateway $gateway `
  -dnsServers $dnsServers #domain + cluster DNSl
}


#### (D): Executes the config,validates the settings of the config file
& {
    Set-AksHciConfig -imageDir "$csv_path\imageDir" -workingDir "$csv_path\workingDir" -cloudConfigLocation "$csv_path\cloudConfig" -vnet $vnet -cloudservicecidr $cloudservicecidr
}

#END---

################################################# S5: Setting the resource group that will be used for registering the AKS system ##############################################################################################################################

#### (A): To select the resource group
# Specifying the resource group that we'd want to use for registering the AKS system.

#START---

& {
    $subscription = Get-AzContext

    Write-Host "Selecting RG for registration" -ForegroundColor Green
    $RG = Get-Option "Get-AzResourceGroup" "ResourceGroupName"
}
#END---

################################################# S6: Set up the registration of an Azure Stack HCI host with the AKS engine #############################################################
# Sets the AKS Registry + install the AKS HCI

#START---
& {
    Set-AksHciRegistration -subscriptionId $($subscription.Subscription.Id) -resourceGroupName $RG      -# to register the Azure Stack HCI host with the Azure Kubernetes Service (AKS) engine, specifies the name of the Azure Resource Group to use for the registration.
    Install-AksHci -Verbose                                                                             -# installs the AKS engine on Azure Stack HCI and sets up a Kubernetes cluster + more detail of the installation process.

}
#END---


################################################# S6: (OPTIONAL) - Creating a workload cluster #############################################################
# Can be used for publishing containers on the cluster
#START---
$FormatEnumerationLimit = -1

Get-AksHciKubernetesVersion
(Get-Command New-AksHciCluster).Parameters.Values | Select-Object Name


$aksHciClusterName = "myk8s-wrkloadclus-$(Get-Random -Minimum 100 -Maximum 999)"

New-AksHciCluster -Name $aksHciClusterName -nodeCount 1 -osType linux -primaryNetworkPlugin calico

Get-akshcicredential -name $aksHciClusterName -Confirm:$false
Get-ChildItem $env:userprofile\.kube

enable-akshciarcconnection -name $aksHciClusterName
#END---



################################################# S7: Azure Arch Bridge Deployment on node #######################################################################################################################################

#### (A): (Potential dependancy) Installation of Azure CLI on node. [Can be skipped if already installed]

#START---
& {
    $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; Remove-Item .\AzureCLI.msi
    $env:Path += "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
    [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")                # sets the path to environmental variable as theres a chance it's not programmed in
}
#END---


################################################## S8: Azure Resource Bridge Installation #########################################################################################################################################
# Installs Azure arc bridge on Azure stack HCI deploymenet. This enables communication and resource management/deployment using Azure resource bridge.
# Sets the variabels - v-switch,sub ID,resource group name,location,upgrades the ARB related extensions and registers the required azure providrr.
#START----

& {
    Write-Host -ForegroundColor green "Prepare Azure Resource Bridge installation"

    #Vars

    $vSwitchName = Get-Option "Get-VMSwitch" "NameofSwitch"
    $SubscriptionId = $((Get-AzContext).Subscription.Id)
    $resource_group = $RG         # for custom resource group use or pre-created ones in Azure
    $Location = "north-europe"     # Must be an ARB supported region
    $customloc_name = "HCIonprem" # custom location name - change to area where azure stack is deployed

    $ARBPath = "$csv_path\ResourceBridge"          # path of where resources get put in

    $resource_name = ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"
    if (!(Test-Path "$ARBPath"))
    {
        Write-Output "Create ARB path"
        mkdir "$ARBPath"
    }

    $arcbridge_vipPoolStart = "192.168.177.51"        # Virtual IP pool - used to allocate IP addresses to the Kubernetes cluster API server.
    $arcbridge_vipPoolEnd = "192.168.177.59"          # https://docs.microsoft.com/en-us/azure-stack/hci/manage/deploy-arc-resource-bridge-using-command-line

    $ipAddressPrefix = "192.168.177.0/24"
    $gateway = "192.168.177.1"
    $dnsServers = "192.168.177.200"
    $controlPlaneIP = "192.168.177.204"         #used for API

    Initialize-MocNode
    Install-Module -Name ArcHci -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense  # Important: Should be >= 0.2.10
    Get-Module -Name ArcHci -ListAvailable

    New-ArcHciConfigFiles -subscriptionID $SubscriptionId -location $location -resourceGroup $resource_group `                             #Generate YAML file for static IP-based Azure Arc Resource Bridge, VLAN, and proxy settings with username/password-based authentication
        -resourceName $resource_name -workDirectory "$ARBPath" `
        -vipPoolStart $arcbridge_vipPoolStart -vipPoolEnd $arcbridge_vipPoolEnd `
        -dnsServers $dnsServers -vSwitchName $vSwitchName -gateway $gateway -ipAddressPrefix $ipAddressPrefix -vnetName myaksnetwork `
        -k8sNodeIpPoolStart $arcbridge_k8sNodeIpPoolStart -k8sNodeIpPoolEnd $arcbridge_k8sNodeIpPoolEnd -controlPlaneIP $controlPlaneIP #-vlanid

    az login --use-device-code
    az account set --subscription $SubscriptionId

    az extension remove --name arcappliance --verbose
    az extension remove --name connectedk8s --verbose
    az extension remove --name k8s-configuration --verbose
    az extension remove --name k8s-extension --verbose
    az extension remove --name customlocation --verbose
    az extension remove --name azurestackhci --verbose

    az extension add --upgrade --name arcappliance --verbose
    az extension add --upgrade --name connectedk8s --verbose
    az extension add --upgrade --name k8s-configuration --verbose
    az extension add --upgrade --name k8s-extension --verbose
    az extension add --upgrade --name customlocation --verbose
    az extension add --upgrade --name azurestackhci --verbose

    az provider register --namespace Microsoft.Kubernetes
    az provider register --namespace Microsoft.KubernetesConfiguration
    az provider register --namespace Microsoft.ExtendedLocation
    az provider register --namespace Microsoft.ResourceConnector
    az provider register --namespace Microsoft.AzureStackHCI
    az feature register --namespace Microsoft.ResourceConnector --name Appliances-ppauto
    az provider register -n Microsoft.ResourceConnector
}
#END---



################################################## S9: Azure Resource Bridge Installation #########################################################################################################################################

# PREPARE - Download appliance to Resource Bridge folder
#START---
& {
    az arcappliance prepare hci --config-file "$ARBPath\hci-appliance.yaml" --verbose
}
#END---

#DEPLOY - Deploy Arc Bridge
#START---
& {
    az arcappliance deploy hci --config-file  "$ARBPath\hci-appliance.yaml" --outfile "$env:USERPROFILE\.kube\config"
}
#END---


#CREATE - Create Arc Bridge
#START---
& {
    az arcappliance create hci --config-file "$ARBPath\hci-appliance.yaml" --kubeconfig "$env:USERPROFILE\.kube\config"
}
#END---

#STATUS CHECK OF AZURE ARC
#START---
& {
    az arcappliance show --resource-group $resource_group --name $resource_name
}
#END---


################################################### S10:  Get HCI-VM-0perator extension imported #########################################################################################################################################
# This script snippet creates a Kubernetes extension in an Azure Stack HCI cluster
#START---
& {
    $hciClusterId = (Get-AzureStackHci).AzureResourceUri
    #$resource_name = ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"
    az k8s-extension create --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator --extension-type Microsoft.AZStackHCI.Operator --scope cluster --release-namespace helm-operator2 --configuration-settings Microsoft.CustomLocation.ServiceAccount = hci-vmoperator --configuration-protected-settings-file "$ARBPath\hci-config.json" --configuration-settings HCIClusterID = $hciClusterId --auto-upgrade true
}
#END---

#VERIFY the extension is installed
#START---
& {
    az k8s-extension show --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator
}
#END---

################################################### S11: Custom location creation for variable   #########################################################################################################################################
# creates a custom location resource in the specified resource group with the given name. The custom location resource is associated with an Azure Stack HCI cluster appliance.

#START---
& {
    az customlocation create --resource-group $resource_group --name $customloc_name --cluster-extension-ids "/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ResourceConnector/appliances/$resource_name/providers/Microsoft.KubernetesConfiguration/extensions/hci-vmoperator" --namespace hci-vmoperator --host-resource-id "/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ResourceConnector/appliances/$resource_name" --location $Location
}
#END---




################################################### S12: Deploy Azure Resouce Bridge Network #########################################################################################################################################
# Creates a virtual network in an Azure Stack HCI environment

#START---
& {
    az azurestackhci virtualnetwork create --subscription $SubscriptionId --resource-group $resource_group --extended-location name="/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customloc_name" type="CustomLocation" --location $Location --network-type "Transparent" --name $vswitchName

}
#END---


################################################### S13: Deploy Azure Resouce Bridge Virtual Machine image #########################################################################################################################################

#START---
& {
    $galleryImageName = "custom-win2k22-server"
    $galleryImageSourcePath = "$csv_path\ArcBridgeImages\W2k22.vhdx"
    $osType = "Windows"

    if (!(Test-Path $galleryImageSourcePath))
    {
        "You don't have an vhdx or your galleryImageSourcePath is incorrect."
    }
}
#END---

#CREATE IMG
& {
    az azurestackhci galleryimage create --subscription $SubscriptionId --resource-group $resource_group --extended-location name="/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customloc_name" type="CustomLocation" --location $Location --image-path $galleryImageSourcePath --name $galleryImageName --os-type $osType

}
 #>