# Quick script to import CloudWatch log groups
# Run this from the infra directory

Write-Host "Importing CloudWatch log groups..." -ForegroundColor Green

$logGroups = @(
    @{Resource = "aws_cloudwatch_log_group.ingest_lambda_logs"; Name = "/aws/lambda/ExchangeIngest"},
    @{Resource = "aws_cloudwatch_log_group.matcher_lambda_logs"; Name = "/aws/lambda/ExchangeMatcher"},
    @{Resource = "aws_cloudwatch_log_group.ws_handler_logs"; Name = "/aws/lambda/ExchangeWSHandler"},
    @{Resource = "aws_cloudwatch_log_group.trade_broadcaster_logs"; Name = "/aws/lambda/ExchangeTradeBroadcaster"}
)

foreach ($lg in $logGroups) {
    Write-Host "Importing $($lg.Name)..." -ForegroundColor Yellow
    terraform import $lg.Resource $lg.Name
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Successfully imported" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to import (may not exist yet)" -ForegroundColor Yellow
    }
}

Write-Host "`nDone! Run 'terraform plan' to verify." -ForegroundColor Green

