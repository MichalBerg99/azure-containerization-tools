if (-not (Get-Command ConvertTo-Yaml -ErrorAction SilentlyContinue)) {
    [System.Windows.MessageBox]::Show("The powershell-yaml module is required. Please install it using 'Install-Module -Name powershell-yaml'.")
    return
}

# Load WPF and required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

# Define WPF XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Application Deployment" Height="500" Width="500">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>
        <Label Grid.Row="0" Grid.Column="0" Content="Resource Group:" />
        <ComboBox Grid.Row="0" Grid.Column="1" Name="ResourceGroupComboBox" Margin="5" />
        <Label Grid.Row="1" Grid.Column="0" Content="Git Repository:" />
        <TextBox Grid.Row="1" Grid.Column="1" Name="GitRepoTextBox" Margin="5" />

        <Label Grid.Row="2" Grid.Column="0" Content="Branch Name (Optional):" />
        <TextBox Grid.Row="2" Grid.Column="1" Name="BranchNameTextBox" Margin="5" />

        <Label Grid.Row="3" Grid.Column="0" Content="Azure Container Registry (ACR) Name:" />
        <ComboBox Grid.Row="3" Grid.Column="1" Name="ACRNameComboBox" Margin="5" />
        <Label Grid.Row="4" Grid.Column="0" Content="Azure Kubernetes Service (AKS) Name:" />
        <ComboBox Grid.Row="4" Grid.Column="1" Name="AKSNameComboBox" Margin="5" />
        <Label Grid.Row="5" Grid.Column="0" Content="Namespace (Optional):" />
        <TextBox Grid.Row="5" Grid.Column="1" Name="NamespaceTextBox" Margin="5" />
        <Label Grid.Row="6" Grid.Column="0" Content="Networking Capabilities:" />
        <ListBox Grid.Row="6" Grid.Column="1" Name="NetworkingCapabilitiesListBox" Margin="5" SelectionMode="Multiple">
            <ListBoxItem>Storage Account</ListBoxItem>
            <ListBoxItem>Redis</ListBoxItem>
            <ListBoxItem>Database</ListBoxItem>
        </ListBox>
        <StackPanel Grid.Row="7" Grid.Column="1" Name="StorageAccountPanel" Margin="5" >
            <Label Content="Storage Account:" />
            <ComboBox Name="StorageAccountComboBox" />
        </StackPanel>
        <Button Grid.Row="8" Grid.Column="1" Name="DeployButton" Content="Deploy" Margin="5" />
    </Grid>
</Window>
"@

# Create WPF window
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Find WPF elements
$resourceGroupComboBox = $window.FindName('ResourceGroupComboBox')
$gitRepoTextBox = $window.FindName('GitRepoTextBox')
$acrNameComboBox = $window.FindName('ACRNameComboBox')
$aksNameComboBox = $window.FindName('AKSNameComboBox')
$namespaceTextBox = $window.FindName('NamespaceTextBox')
$branchNameTextBox = $window.FindName('BranchNameTextBox')
$networkingCapabilitiesListBox = $window.FindName('NetworkingCapabilitiesListBox')
$storageAccountPanel = $window.FindName('StorageAccountPanel')
$storageAccountComboBox = $window.FindName('StorageAccountComboBox')
$deployButton = $window.FindName('DeployButton')

# Get existing resource groups, ACRs, and AKS clusters

$tenantId = "ace1cb30-a5d7-4184-95b2-800ff3963db0"
Connect-AzAccount -TenantId $tenantId
# Connect-AzAccount
$allResourceGroups = Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName
$resourceGroupComboBox.ItemsSource = $allResourceGroups


$resourceGroupComboBox.Add_SelectionChanged({
    $selectedResourceGroup = $resourceGroupComboBox.SelectedItem

    if ($selectedResourceGroup) {
        # Get ACRs and AKS clusters in the selected resource group
        $allAcrs = Get-AzContainerRegistry -ResourceGroupName $selectedResourceGroup
        $allAks = Get-AzAksCluster -ResourceGroupName $selectedResourceGroup
         # Get storage accounts and databases in the selected resource group
        $allStorageAccounts = Get-AzStorageAccount -ResourceGroupName $selectedResourceGroup

        # Populate the ACR, AKS, Storage account ComboBoxes
        $acrNameComboBox.Items.Clear()
        $aksNameComboBox.Items.Clear()
        # Populate the  and database ComboBoxes
        $storageAccountComboBox.Items.Clear()

        foreach ($acr in $allAcrs) {
            $acrNameComboBox.Items.Add($acr.Name) | Out-Null
        }
        foreach ($aks in $allAks) {
            $aksNameComboBox.Items.Add($aks.Name) | Out-Null
        }

        foreach ($storageAccount in $allStorageAccounts) {
            $storageAccountComboBox.Items.Add($storageAccount.StorageAccountName) | Out-Null
        }
    }
})


# Deploy button click event handler
$deployButton.Add_Click({
$gitRepo = $gitRepoTextBox.Text
$acrName = $acrNameComboBox.SelectedItem.ToLower()
$aksName = $aksNameComboBox.SelectedItem
$networkingCapabilities = $networkingCapabilitiesListBox.SelectedItems
$selectedResourceGroup = $resourceGroupComboBox.SelectedItem
$namespace = $namespaceTextBox.Text
if (-not $namespace) {
    $namespace = "default"
}
$branchName = $branchNameTextBox.Text

Write-Host "Namespace: $namespace"


# Deploy the container image to AKS
$aks = Get-AzAksCluster -Name $aksName -ResourceGroupName $selectedResourceGroup
az aks get-credentials --name $aksName --resource-group $selectedResourceGroup 2>&1

# Create the namespace if it doesn't exist
$namespaceExists = kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | Where-Object { $_ -eq $namespace }

if (-not $namespaceExists) {
    kubectl create namespace $namespace
}


if (-not ($selectedResourceGroup -and $gitRepo -and $acrName -and $aksName)) {
    [System.Windows.MessageBox]::Show("All fields must be filled in.")
    return
}

# Test the Git repository URL
    $gitRepoTest = git ls-remote -q $gitRepo 2>&1
    if ($gitRepoTest -like "*fatal:*") {
        [System.Windows.MessageBox]::Show("Invalid Git repository URL. Please provide a valid URL.")
        return
    }

# Clone the Git repository
$tempFolder = New-Item -ItemType Directory -Path (Join-Path $env:TEMP (Get-Random))
git clone $gitRepo $tempFolder 2>&1

# Switch to the specified remote branch if provided
if ($branchName) {
    git -C $tempFolder fetch origin $branchName 2>&1
    git -C $tempFolder checkout -t "origin/$branchName" 2>&1
}

# Login to Azure
Connect-AzAccount -TenantId $tenantId

# Build and push the container image to ACR
$acr = Get-AzContainerRegistry -Name $acrName -ResourceGroupName $selectedResourceGroup
az acr login --name $acrName
$imageName = "$($acr.LoginServer)/app:latest"
docker build -t $imageName $tempFolder 2>&1
Write-host "Building Docker image"
Start-Sleep -Seconds 5
Write-host "Pushing the Docker image"
docker push $imageName 2>&1
Write-host "Docker image has been pushed to the container registry"


# Apply networking capabilities
$envVars = @()
if ($networkingCapabilities -like "*Storage Account") {
    $selectedStorageAccount = $storageAccountComboBox.SelectedItem
    if ($selectedStorageAccount) {
        $storageAccountConnectionString = (Get-AzStorageAccount -Name $selectedStorageAccount -ResourceGroupName $selectedResourceGroup).Context.ConnectionString
        $envYaml += @"
        - name: STORAGE_ACCOUNT_CONNECTION_STRING
          value: "$storageAccountConnectionString"
"@
    }
}

$redisContainerYaml = ""
# Stores the Redis container YAML definition if Redis is selected
if ($networkingCapabilities -like "*Redis") {
    $envYaml += @"
        - name: REDIS_HOST
          value: "redis"
"@

    $redisContainerYaml = @"

---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: $namespace
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: $namespace
spec:
  selector:
    matchLabels:
      app: redis
  replicas: 1
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:6.2
          ports:
            - containerPort: 6379
"@
}


Write-Host "Preparing environment variables for YAML deployment"

$deploymentYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
  namespace: $namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
      - name: app-container
        image: $imageName
        env:
$envYaml
"@


$deploymentYaml += $redisContainerYaml

Write-Host "Creating deployment YAML with environment variables"

Set-Content -Path "$tempFolder\deployment.yaml" -Value $deploymentYaml
Write-Host "Saving deployment YAML file to disk"
kubectl apply -f "$tempFolder\deployment.yaml" --namespace=$namespace
Write-Host "Applying deployment YAML to Azure Kubernetes Cluster"
# Clean up
Remove-Item -Recurse -Force $tempFolder

# Show success message
[System.Windows.MessageBox]::Show("Deployment completed!")

})

# Show WPF window
$window.ShowDialog() | Out-Null