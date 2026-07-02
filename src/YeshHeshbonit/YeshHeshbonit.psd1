@{
    RootModule        = 'YeshHeshbonit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'e1a9c2b4-7f3d-4a6e-9b0c-2d8f5e1a7c3b'
    Author            = 'Eitan / SouliTEK'
    Description       = 'Per-invoice tax set-aside calculator over the yeshinvoice.co.il API (VAT / mikdamot / Bituach Leumi).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-TaxSummary', 'Get-YeshInvoice', 'Export-TaxSummary', 'Get-DashboardSummaryResponse', 'Get-DashboardCsvResponse', 'Get-DashboardRatesResponse', 'Set-DashboardRatesResponse', 'Start-TaxDashboard')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
