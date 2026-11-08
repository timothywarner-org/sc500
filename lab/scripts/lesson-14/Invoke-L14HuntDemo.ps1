<#
.SYNOPSIS
    Demo 14.3: one hypothesis carried through saved hunting queries, the investigation workbook,
    and a notebook that ends in a short report.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-14/evidence/):
      Queries   Read-only. The two saved hunting queries read back from the workspace, then run:
                ServiceHub exports with no service case (by actor), and key reads on the Lesson 12
                parts-export store from the Azure Activity log. Caller IP addresses stay out.
      Workbook  Read-only. The workbook read back (name, category, workspace) and each of its
                queries run once, so the prep records what the tiles show today.
      Notebook  Runs lab/notebooks/lesson-14/ServiceHub-Export-Hunt.ipynb headless with nbconvert,
                using your Azure CLI sign-in. The executed copy (with outputs) is saved as private
                evidence; the notebook in Git stays output-free.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14HuntDemo.ps1 -Mode Queries
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Queries', 'Workbook', 'Notebook')][string]$Mode)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
$l13 = Get-L14L13Lab
$lab = Get-L14Outputs

switch ($Mode) {
    'Queries' {
        $results = [ordered]@{}
        foreach ($name in @($cfg.names.huntExportActor, $cfg.names.huntStoreKeys)) {
            $s = Invoke-L14Rest -Path "$($l13.workspaceId)/savedSearches/$name`?api-version=2020-08-01"
            $tactics = @($s.properties.tags | Where-Object name -eq 'tactics' | ForEach-Object value) -join ''
            Write-Host "== $($s.properties.displayName)  [$($s.properties.category); $tactics]"
            $rows = @(Invoke-L14Query -Lab $l13 -Kql $s.properties.query -Timespan 'P7D')
            if ($rows) { $rows | Format-Table -AutoSize | Out-String -Width 220 | Out-Host } else { Write-Host '  (no rows in the last 7 days)' }
            $results[$name] = [ordered]@{ displayName = $s.properties.displayName; category = $s.properties.category; tactics = $tactics; rows = $rows }
        }
        [void](Write-L14Evidence 'hunt-queries' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); queries = $results }))
    }
    'Workbook' {
        $w = Invoke-L14Rest -Path "$($lab.workbookId)?api-version=2022-04-01&canFetchContent=true"
        $data = $w.properties.serializedData | ConvertFrom-Json -Depth 50
        Write-Host "Workbook: $($w.properties.displayName)  category $($w.properties.category), source $(($w.properties.sourceId -split '/')[-1])"
        $tiles = foreach ($item in @($data.items | Where-Object type -eq 3)) {
            $rows = @(Invoke-L14Query -Lab $l13 -Kql $item.content.query -Timespan 'P7D')
            [pscustomobject][ordered]@{ Tile = $item.content.title; Visualization = $item.content.visualization; Rows = $rows.Count }
        }
        $tiles | Format-Table -AutoSize | Out-Host
        Write-Host 'Open it in the Defender portal: Microsoft Sentinel > Threat management > Workbooks > My workbooks. That page shows only the primary workspace, which this one is.'
        [void](Write-L14Evidence 'workbook' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); name = $w.properties.displayName; category = $w.properties.category; sourceId = $w.properties.sourceId; tiles = $tiles }))
    }
    'Notebook' {
        $nb = Join-Path $script:L14Lab 'notebooks/lesson-14/ServiceHub-Export-Hunt.ipynb'
        if (-not (Test-Path -LiteralPath (Join-Path $script:L14State 'notebook-params.json'))) { throw 'Run Deploy-L14Lab.ps1 -Deploy first; it writes the notebook''s private parameters file.' }
        [void][IO.Directory]::CreateDirectory($script:L14Evidence)
        $outName = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-notebook-executed'
        $started = [DateTime]::UtcNow
        & python -m jupyter nbconvert --to notebook --execute $nb --output-dir $script:L14Evidence --output $outName --ExecutePreprocessor.timeout=180 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "The notebook did not run to the end (nbconvert exit $LASTEXITCODE)." }
        $executed = Join-Path $script:L14Evidence "$outName.ipynb"
        $cells = (Get-Content -LiteralPath $executed -Raw | ConvertFrom-Json -Depth 50).cells
        $errors = @($cells | Where-Object { $_.cell_type -eq 'code' } | ForEach-Object { $_.outputs } | Where-Object { $_.output_type -eq 'error' })
        $report = @($cells[-1].outputs | ForEach-Object { $_.data.'text/markdown' }) -join ''
        Write-Host '--- report cell'
        Write-Host $report
        [void](Write-L14Evidence 'notebook' ([ordered]@{ ranUtc = $started.ToString('o'); seconds = [math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 1); executedCopy = $executed; errors = $errors.Count; report = $report }))
        if ($errors) { throw "The notebook reported $($errors.Count) error output(s); open $executed." }
    }
}
