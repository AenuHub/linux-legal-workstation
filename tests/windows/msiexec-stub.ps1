param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
if ($env:LW_MSIEXEC_LOG) { Add-Content -LiteralPath $env:LW_MSIEXEC_LOG -Value ($Rest -join ' ') }
if ($Rest -contains '{GONE}') { exit 1605 }   # urun kurulu degil (Review Focus 5)
exit 0
