# Install AzureRM module if not avaliable
if (Get-Module -ListAvailable -Name Az) {
    Write-Host "Az is installed, proceeding..."
} else {
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
            Write-Warning -Message ('Az module not installed. Having both the AzureRM and ' +
              'Az modules installed at the same time is not supported.')
        } else {
            Install-Module -Name Az -AllowClobber -Scope CurrentUser
        }
    }
    catch [Exception] {
        $_.message 
        exit
    }
}

# Install PSYaml if not available
if (Get-Module -ListAvailable -Name powershell-yaml) {
    Write-Host "powershell-yaml is installed, proceeding..."
} else {
    try {
        Write-Host "powershell-yaml is required, installing..."
        Install-Module -Name powershell-yaml -AllowClobber -Confirm:$False -Force  
    }
    catch [Exception] {
        $_.message 
        exit
    }
}

Import-Module powershell-yaml

$scriptPath = Get-Location

$policyFolderName = Read-Host 'Please provide name of the policy folder you wish to remove'

$policiesFolder = 'policies'
$policyFilename = 'policy.json'
$workflowsLocation = '.github/workflows'

$policyPath = $policiesFolder + '/' + $policyFolderName;
$relativePolicyPath = '../' + $policyPath;
$absolutePolicyPath = (Resolve-Path -Path $relativePolicyPath).Path
$absolutePolicyJsonPath = $absolutePolicyPath + '/' + $policyFilename

if (!(Test-Path $absolutePolicyPath -PathType Container)) {
    Write-Output 'There is no policy with passed folder name.'
    exit
}

if (!(Test-Path $absolutePolicyJsonPath -PathType Leaf)) {
    Write-Output 'There is no policy file within passed folder.'
    exit
}

Start-Transaction

try {
    # Connect to Azure with a browser sign in token
    Connect-AzAccount

    # Get policy identifier
    Set-Location $relativePolicyPath
    $policyJson = Get-Content $policyFilename | Out-String | ConvertFrom-Json

    if (!$policyJson.id) {
        Write-Output 'Policy JSON does not contain valid "id" field.'
        exit
    }

    $policyId = $policyJson.id

    # Remove all references in workflows and remove empty workflows
    Set-Location ('../../' + $workflowsLocation)
    $workflows = Get-ChildItem '.'

    foreach($workflow in $workflows) {
        # Remove policy path from workflow file
        (Get-Content $workflow.Name) -notmatch $policyPath | Set-Content $workflow.Name

        # Remove workflow if all of the associated paths has been removed, rewrite paths otherwise
        $workflowObject = Get-Content $workflow.Name | ConvertFrom-Yaml -AllDocuments
        $workflowAssociatedPaths = $workflowObject.jobs.'apply-azure-policy'.steps.Where({$_.name -eq 'Create or Update Azure Policies'}).with.paths.Split([Environment]::NewLine).Where({$_ -ne '' })

        if ($workflowAssociatedPaths.length -lt 1) {
            Remove-Item $workflow.Name
        }
    }

    # Use Azure cmdlet to remove policy in the Azure portal
    Remove-AzPolicyDefinition -Id $policyId

    # Remove policy folder
    Set-Location '..'
    Remove-Item $policyFolderName
}
catch [Exception] {
    Write-Output $_.Exception.Message
    Undo-Transaction
    Set-Location $scriptPath
    exit
}

Complete-Transaction
Set-Location $scriptPath
Write-Host 'Policy in folder ' + $policyFolderName + ' has been successfully removed.'
exit



