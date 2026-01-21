# PowerShell script to generate forecasts for all 100 product-store combinations
Write-Host "=== Forecast Generation Script ===" -ForegroundColor Cyan

# Step 1: Delete all existing forecasts
Write-Host "`n[1/3] Clearing existing forecasts..." -ForegroundColor Yellow
$deleteResult = docker exec inventory-mongo mongosh inventory_db --quiet --eval "db.forecasts.deleteMany({})"
Write-Host $deleteResult

# Step 2: Generate forecasts for all products
Write-Host "`n[2/3] Generating forecasts for 100 product-store combinations..." -ForegroundColor Yellow
$total = 0
$success = 0
$failed = @()

for ($i = 1; $i -le 20; $i++) {
    $productId = "P" + $i.ToString("0000")
    
    foreach ($storeId in @('S001', 'S002', 'S003', 'S004', 'S005')) {
        $total++
        $inventory = Get-Random -Minimum 150 -Maximum 500
        
        try {
            # Fetch historical data from MongoDB
            $mongoQuery = @"
db.historicaldatas.find({productId: '$productId', storeId: '$storeId'}).sort({date: 1}).toArray()
"@
            $historicalJson = docker exec inventory-mongo mongosh inventory_db --quiet --eval $mongoQuery
            
            # Parse historical data
            $historicalData = @()
            if ($historicalJson -and $historicalJson -ne "null") {
                $historical = $historicalJson | ConvertFrom-Json
                foreach ($record in $historical) {
                    $historicalData += @{
                        date = $record.date.ToString("yyyy-MM-dd")
                        units_sold = $record.unitsSold
                        inventory_level = $record.inventoryLevel
                        price = $record.price
                        discount = $record.discount
                        weather_condition = $record.weatherCondition
                        seasonality = $record.seasonality
                        category = $record.category
                        region = $record.region
                    }
                }
            }
            
            # Call ML service with historical data
            $mlBody = @{
                product_id = $productId
                store_id = $storeId
                current_date = '2024-01-01'
                current_inventory = $inventory
                historical_data = $historicalData
            } | ConvertTo-Json -Depth 10
            
            $ml = Invoke-RestMethod -Uri "http://localhost:5001/api/ml/predict/realtime" `
                -Method POST `
                -ContentType "application/json" `
                -Body $mlBody `
                -ErrorAction Stop
            
            # Prepare data for MongoDB
            $predictions = ($ml.forecast | ForEach-Object { $_ }) -join ','
            $dates = ($ml.dates | ForEach-Object { "'$_'" }) -join ','
            $reason = $ml.inventory_metrics.order_reason -replace "'", "\'"
            $statusMsg = $ml.inventory_metrics.statusMessage -replace "'", "\'"
            
            # Build MongoDB command
            $mongoCmd = @"
db.forecasts.insertOne({
  productId: '$productId',
  storeId: '$storeId',
  predictions: [$predictions],
  dates: [$dates],
  safetyStock: $($ml.inventory_metrics.safety_stock),
  reorderPoint: $($ml.inventory_metrics.reorder_point),
  inventoryMetrics: {
    order_date: '$($ml.inventory_metrics.order_date)',
    order_quantity: $($ml.inventory_metrics.order_quantity),
    days_until_order: $($ml.inventory_metrics.days_until_order),
    order_reason: '$reason',
    should_order_now: $($ml.inventory_metrics.should_order_now.ToString().ToLower()),
    avg_daily_demand: $($ml.inventory_metrics.avg_daily_demand),
    forecasted_demand_30d: $($ml.inventory_metrics.forecasted_demand_30d),
    currentInventory: $($ml.inventory_metrics.current_inventory),
    daysOfStock: $($ml.inventory_metrics.days_of_stock),
    stockoutRisk: $($ml.inventory_metrics.stockout_risk.ToString().ToLower()),
    overstockRisk: $($ml.inventory_metrics.overstock_risk.ToString().ToLower()),
    status: '$($ml.inventory_metrics.status)',
    statusMessage: '$statusMsg'
  },
  modelUsed: '$($ml.model_used)',
  generatedAt: new Date()
})
"@
            
            # Insert to MongoDB
            docker exec inventory-mongo mongosh inventory_db --quiet --eval $mongoCmd | Out-Null
            
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

# Step 3: Summary
Write-Host "`n`n[3/3] Summary:" -ForegroundColor Yellow
Write-Host "Total: $total forecasts"
Write-Host "Success: $success forecasts" -ForegroundColor Green
Write-Host "Failed: $($failed.Count) forecasts" -ForegroundColor Red

if ($failed.Count -gt 0 -and $failed.Count -le 10) {
    Write-Host "`nFailed products:"
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

# Verify database
Write-Host "`n[Verification] Checking database..." -ForegroundColor Cyan
$verifyCmd = "db.forecasts.aggregate([{`$group:{_id:null,count:{`$sum:1},has_30d_demand:{`$sum:{`$cond:[{`$gt:['`$inventoryMetrics.forecasted_demand_30d',0]},1,0]}},has_order_date:{`$sum:{`$cond:[{`$ne:['`$inventoryMetrics.order_date',null]},1,0]}}}}])"
$verifyResult = docker exec inventory-mongo mongosh inventory_db --quiet --eval $verifyCmd

Write-Host $verifyResult
Write-Host "`n=== Forecast Generation Complete ===" -ForegroundColor Cyan
