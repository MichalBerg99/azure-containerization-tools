# Log in to your Azure account with a specific tenant
try {

$tenantId = "ace1cb30-a5d7-4184-95b2-800ff3963db0"
Connect-AzAccount -TenantId $tenantId

# Load the required assemblies for WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing

# XAML for WPF form
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Enter Variables" Height="420" Width="400">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="10">
                <TextBlock Text="Resource Group:" />
                <TextBox x:Name="ResourceGroup" />

                <TextBlock Text="Location:" Margin="0,10,0,0" />
                <ComboBox x:Name="Location" />
                
                <TextBlock Text="Container Registry Name:" Margin="0,10,0,0" />
                <TextBox x:Name="ContainerRegistryName" />

                <TextBlock Text="AKS Cluster Name:" Margin="0,10,0,0" />
                <TextBox x:Name="AKSClusterName" />

                <TextBlock Text="Node Count:" Margin="0,10,0,0" />
                <ComboBox x:Name="NodeCount" />

                <TextBlock Text="Existing Resource Group:" Margin="0,10,0,0" />
                <StackPanel Orientation="Horizontal">
                    <ComboBox x:Name="ExistingResourceGroup" Width="250" IsEnabled="False" />
                    <CheckBox x:Name="UseExistingResourceGroup" Content="Use Existing" Margin="10,0,0,0" />
                </StackPanel>
                
                <TextBlock Text="Existing Container Registry:" Margin="0,10,0,0" />
                <StackPanel Orientation="Horizontal">
                    <ComboBox x:Name="ExistingContainerRegistry" Width="250" IsEnabled="False" />
                    <CheckBox x:Name="UseExistingContainerRegistry" Content="Use Existing" Margin="10,0,0,0" />
                </StackPanel>
            </StackPanel>
        </ScrollViewer>
        <Button x:Name="OkButton" Content="OK" Grid.Row="2" Width="75" Height="23" Margin="10" HorizontalAlignment="Right" />
    </Grid>
</Window>
"@

# Create WPF form and add controls
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$form = [Windows.Markup.XamlReader]::Load($reader)

# Assign variables to WPF controls
$ResourceGroup = $form.FindName("ResourceGroup")
$Location = $form.FindName("Location")
$ContainerRegistryName = $form.FindName("ContainerRegistryName")
$AKSClusterName = $form.FindName("AKSClusterName")
$NodeCount = $form.FindName("NodeCount")
$ExistingResourceGroup = $form.FindName("ExistingResourceGroup")
$UseExistingResourceGroup = $form.FindName("UseExistingResourceGroup")
$ExistingContainerRegistry = $form.FindName("ExistingContainerRegistry")
$UseExistingContainerRegistry = $form.FindName("UseExistingContainerRegistry")
$OkButton = $form.FindName("OkButton")

# Fill the comboboxes
$locations = (Get-AzLocation).Location
$Location.ItemsSource = $locations
$NodeCount.ItemsSource = @(1..1000)

$existingResourceGroups = Get-AzResourceGroup
$ExistingResourceGroup.ItemsSource = $existingResourceGroups.ResourceGroupName
$existingContainerRegistries = Get-AzContainerRegistry
foreach ($acr in $existingContainerRegistries) {
    $ExistingContainerRegistry.Items.Add($acr.Name)
}

# Waits forr resources to be created and retries if the resources does'nt exist yet
function Wait-Resource {
    param (
        [string]$ResourceType,
        [string]$ResourceName,
        [string]$ResourceGroupName
    )

    $retryIntervalInSeconds = 10
    $maxRetries = 5

    for ($i = 0; $i -lt $maxRetries; $i++) {
        $resource = Get-AzResource -ResourceType $ResourceType -ResourceGroupName $ResourceGroupName -Name $ResourceName -ErrorAction SilentlyContinue

        if ($resource) {
            Write-Host "Resource $($ResourceType) $($ResourceName) is available."
            return
        } else {
            Write-Host "Waiting for resource $($ResourceType) $($ResourceName) to become available..."
            Start-Sleep -Seconds $retryIntervalInSeconds
        }
    }

    # Throw an exception if the resource did not become available
    throw "Resource $($ResourceType) $($ResourceName) did not become available within the specified retries."
}



# Function to enable/disable TextBox controls based on the CheckBox state
$UseExistingResourceGroup.Add_Checked({
    $ResourceGroup.IsEnabled = -not $UseExistingResourceGroup.IsChecked
    $ExistingResourceGroup.IsEnabled = $UseExistingResourceGroup.IsChecked
    $Location.IsEnabled = -not $UseExistingResourceGroup.IsChecked
})
$UseExistingResourceGroup.Add_Unchecked({
    $ResourceGroup.IsEnabled = -not $UseExistingResourceGroup.IsChecked
    $ExistingResourceGroup.IsEnabled = $UseExistingResourceGroup.IsChecked
    $Location.IsEnabled = -not $UseExistingResourceGroup.IsChecked
})
$UseExistingContainerRegistry.Add_Checked({
    $ContainerRegistryName.IsEnabled = -not $UseExistingContainerRegistry.IsChecked
    $ExistingContainerRegistry.IsEnabled = $UseExistingContainerRegistry.IsChecked
})
$UseExistingContainerRegistry.Add_Unchecked({
    $ContainerRegistryName.IsEnabled = -not $UseExistingContainerRegistry.IsChecked
    $ExistingContainerRegistry.IsEnabled = $UseExistingContainerRegistry.IsChecked
})

$OkButton.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})

# Show the form and get the user input
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    # Continue with the rest of the script
    $useExistingResourceGroup = $UseExistingResourceGroup.IsChecked
    $useExistingContainerRegistry = $UseExistingContainerRegistry.IsChecked

    if ($useExistingResourceGroup) {
        $resource_group = $ExistingResourceGroup.Text
    } else {
        $resource_group = $ResourceGroup.Text
    }

    if ($useExistingContainerRegistry) {
        $container_registry_name = $ExistingContainerRegistry.Text
    } else {
        $container_registry_name = $ContainerRegistryName.Text
    }

    $location = $Location.Text
    $aks_cluster_name = $AKSClusterName.Text
    $node_count = $NodeCount.Text
} else {
    # The form was closed, stop the script
    write-host "test"
    return
}

# Convert the $node_count to an integer
$node_count = [int]$node_count

# Check if the Resource Group exists, if not, create one
if (-not $useExistingResourceGroup) {
    New-AzResourceGroup -Name $resource_group -Location $location
}

# Wait-Resource -ResourceType "Microsoft.Resources/resourceGroups" -ResourceGroupName $resource_group
start-sleep 2
# Check if the Container Registry exists, if not, create one
if (-not $useExistingContainerRegistry) {
    New-AzContainerRegistry -ResourceGroupName $resource_group -Name $container_registry_name -Sku Basic -EnableAdminUser
}
Wait-Resource -ResourceType "Microsoft.ContainerRegistry/registries" -ResourceGroupName $resource_group -ResourceName $container_registry_name

# Login to the Container Registry
$credentials = Get-AzContainerRegistryCredential -ResourceGroupName $resource_group -Name $container_registry_name

# Get the login server address of the container registry
$acr_login_server = (Get-AzContainerRegistry -ResourceGroupName $resource_group -Name $container_registry_name).LoginServer

# Create an AKS cluster with a custom node count
az aks create -n $aks_cluster_name -g $resource_group --generate-ssh-keys --attach-acr $container_registry_name --node-vm-size Standard_B2s

# Wait for the AKS cluster and container registry to become available
Wait-Resource -ResourceType "Microsoft.ContainerRegistry/registries" -ResourceGroupName $resource_group -ResourceName $container_registry_name
Wait-Resource -ResourceType "Microsoft.ContainerService/managedClusters" -ResourceGroupName $resource_group -ResourceName $aks_cluster_name

# Connect kubectl to the AKS cluster
Import-AzAksCredential -ResourceGroupName $resource_group -Name $aks_cluster_name

Start-Sleep -Seconds 2

# Display an alert to inform the user that the script has finished running
[System.Windows.Forms.MessageBox]::Show('The script has finished running.', 'Script Complete', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

} catch {
    # Catch block to handle exceptions
    $ErrorMessage = $_.Exception.Message
    Write-Host "Error: $ErrorMessage"

    # Display an error message in a message box
    [System.Windows.Forms.MessageBox]::Show("An error occurred: $ErrorMessage", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}