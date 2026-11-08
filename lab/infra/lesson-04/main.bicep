// Lesson 4: Secure Storage and Databases. Subscription-scope entry point.
//
// WHY a subscription-scope file: the lesson owns its own resource group, and creating the
// group in the same deployment means one what-if shows the whole footprint, group included.
// Everything else is in data.bicep at resource-group scope.
//
// The deployment script (scripts/lesson-04/Deploy-L04Lab.ps1) resolves every
// environment-specific value (the operator's object ID, UPN, and public IP, and the role
// definition IDs) and passes them in. Nothing tenant-specific is hard-coded here.
targetScope = 'subscription'

@description('Azure region for every lesson resource.')
param location string

@description('Lesson-owned resource group.')
param resourceGroupName string = 'rg-sc500-l04-data'

@description('Object ID of the operator who plays Kim Akers on camera (the signed-in admin).')
param operatorObjectId string

@description('UPN of that operator, used as the SQL Microsoft Entra admin login name.')
param operatorUpn string

@description('Public IPv4 address of the recording workstation. Used for the SQL firewall rule only; the storage IP rule is added live in demo 4.1.')
param operatorIp string

@description('Region for the SQL server and database. See data.bicep for why it can differ from location.')
param sqlLocation string = location

@description('Built-in role definition IDs resolved by name at deploy time, so a GUID typo cannot grant the wrong role.')
param blobDataReaderRoleId string
param blobDataOwnerRoleId string

@description('False while the Defender for Azure SQL plan is Free. See data.bicep.')
param vulnerabilityAssessmentEnabled bool = true

var tags = {
  course: 'SC500'
  lesson: '04'
  managedBy: 'sc500-l04-iac'
  workload: 'ContosoServiceHub'
  company: 'Contoso'
  lifecycle: 'retain-until-recording-complete'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module data 'data.bicep' = {
  name: 'sc500-lesson04-data'
  scope: rg
  params: {
    location: location
    tags: tags
    operatorObjectId: operatorObjectId
    operatorUpn: operatorUpn
    operatorIp: operatorIp
    sqlLocation: sqlLocation
    blobDataReaderRoleId: blobDataReaderRoleId
    blobDataOwnerRoleId: blobDataOwnerRoleId
    vulnerabilityAssessmentEnabled: vulnerabilityAssessmentEnabled
  }
}

output lab object = data.outputs.lab
