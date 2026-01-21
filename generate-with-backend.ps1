# PowerShell script to generate forecasts using backend API
Write-Host "=== Forecast Generation Script (Using Backend API) ===" -ForegroundColor Cyan

# Step 1: Delete all existing forecasts
Write-Host "`n[1/3] Clearing existing forecasts..." -ForegroundColor Yellow
$deleteResult = docker exec inventory-mongo mongosh inventory_db --quiet --eval "db.forecasts.deleteMany({})"
Write-Host $deleteResult

# Step 2: Generate forecasts for all products using backend API
Write-Host "`n[2/3] Generating forecasts for 100 product-store combinations..." -ForegroundColor Yellow
$total = 0
$success = 0
$failed = @()

for ($i = 1; $i -le 20; $i++) {
    $productId = "P" + $i.ToString("0000")
    
    foreach ($storeId in @('S001', 'S002', 'S003', 'S004', 'S005')) {
        $total++
        
        try {
            # Call backend API (which handles historical data fetching)
            $body = @{
                productId = $productId
                storeId = $storeId
            } | ConvertTo-Json
            
            $response = Invoke-RestMethod -Uri "http://localhost:5000/api/forecasts/generate" `
                -Method POST `
                -ContentType "application/json" `
                -Body $body `
                -ErrorAction Stop
            
            $success++
            if ($success % 10 -eq 0) {
                Write-Host "Progress: $success/$total forecasts generated..." -ForegroundColor Green
            }
            
        } catch {
            $failed += "$productId-$storeId"
            Write-Host "x" -NoNewline -ForegroundColor Red
        }
    }
}

Write-Host "`n`n[3/3] Summary:" -ForegroundColor Yellow
Write-Host "Total attempts: $total" -ForegroundColor White
Write-Host "Successful: $success" -ForegroundColor Green
Write-Host "Failed: $($failed.Count)" -ForegroundColor Red

if ($failed.Count -gt 0) {
    Write-Host "`nFailed products:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" }
}

# Check model distribution
Write-Host "`n[4/4] Checking model usage..." -ForegroundColor Yellow
$modelCheck = docker exec inventory-mongo mongosh inventory_db --quiet --eval "db.forecasts.aggregate([{`$group: {_id: '`$modelUsed', count: {`$sum: 1}}}])"
Write-Host $modelCheck

Write-Host "`n=== Complete! ===" -ForegroundColor Green
