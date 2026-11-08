// The Defender EASM workspace for demo 12.4. The resource itself is empty; the discovery group and its
// seed are data-plane objects that Deploy-L12Lab.ps1 creates through the EASM API after this deploys.
// Creating the first Defender EASM resource starts a 30-day free trial. After that, approved inventory
// assets bill daily, so the lab records the creation date and you delete the workspace before then.
param location string
param workspaceName string
param tags object

resource workspace 'Microsoft.Easm/workspaces@2023-04-01-preview' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {}
}

output lab object = {
  easmResourceGroup: resourceGroup().name
  easmWorkspace: workspace.name
  easmWorkspaceId: workspace.id
  easmLocation: location
}
