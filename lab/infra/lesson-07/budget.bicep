// A monthly cost budget on the lesson's resource group (resource-group scope).
//
// WHY: the Cloud Adoption Framework's governance checklist asks workload teams to set budget alerts
// at the resource group level (CM01), and Lesson 7's real cost risk is a bounded firewall that
// someone forgets to remove (about 1.75 USD an hour). A budget doesn't stop spending; it tells the
// owner early. Alerts go to the Owner role, so no email address lives in a template or a tag.
// Schema: https://learn.microsoft.com/azure/templates/microsoft.consumption/2023-11-01/budgets

@description('Budget name: budget-{resource group name}.')
@minLength(1)
@maxLength(63)
param name string

@description('Monthly amount in the billing currency.')
@minValue(1)
param amount int

@description('First day of a month, yyyy-MM-dd. Budgets must start on the first.')
param startDate string

@description('Percentages of actual cost that send an alert, for example [50, 80, 100].')
param actualThresholds array

@description('Percentage of forecast cost that sends an alert.')
param forecastThreshold int

@description('Azure RBAC roles on this scope that receive the alerts.')
param contactRoles array

// One notification per actual threshold, plus one on the forecast. Keys must be unique strings.
var actualNotifications = reduce(actualThresholds, {}, (acc, t) => union(acc, {
  'actual-${t}': {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: t
    thresholdType: 'Actual'
    contactRoles: contactRoles
  }
}))
var forecastNotification = {
  'forecast-${forecastThreshold}': {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: forecastThreshold
    thresholdType: 'Forecasted'
    contactRoles: contactRoles
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: name
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: union(actualNotifications, forecastNotification)
  }
}

@description('The budget\'s resource ID.')
output budgetId string = budget.id
