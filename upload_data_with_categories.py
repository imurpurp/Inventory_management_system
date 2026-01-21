import pandas as pd
from pymongo import MongoClient
from datetime import datetime

# Connect to MongoDB
client = MongoClient('mongodb://localhost:27017/')
db = client['inventory_db']

# Read CSV
print("Reading CSV...")
df = pd.read_csv('retail_store_inventory.csv')
print(f"Read {len(df)} rows")

# Parse and prepare historical data
print("Preparing historical data...")
historical_data = []
for _, row in df.iterrows():
    doc = {
        'date': pd.to_datetime(row['Date']).to_pydatetime(),
        'storeId': str(row['Store ID']).upper(),
        'productId': str(row['Product ID']).upper(),
        'category': str(row['Category']).strip() if pd.notna(row['Category']) else 'Other',
        'region': str(row['Region']).strip() if pd.notna(row['Region']) else 'Central',
        'unitsSold': float(row['Units Sold']) if pd.notna(row['Units Sold']) else 0,
        'inventoryLevel': float(row['Inventory Level']) if pd.notna(row['Inventory Level']) else 0,
        'demandForecast': float(row['Demand Forecast']) if pd.notna(row['Demand Forecast']) else None,
        'price': float(row['Price']) if pd.notna(row['Price']) else 0,
        'discount': float(row.get('Discount (%)', 0)),
        'weatherCondition': str(row['Weather Condition']).strip() if pd.notna(row.get('Weather Condition')) else 'Clear',
        'seasonality': str(row['Seasonality']).strip() if pd.notna(row.get('Seasonality')) else 'Regular',
        'uploadedAt': datetime.now()
    }
    historical_data.append(doc)

# Insert historical data in batches
print("Inserting historical data...")
batch_size = 1000
for i in range(0, len(historical_data), batch_size):
    batch = historical_data[i:i+batch_size]
    try:
        db.historicaldata.insert_many(batch, ordered=False)
        print(f"Inserted batch {i//batch_size + 1}/{(len(historical_data)-1)//batch_size + 1}")
    except Exception as e:
        if 'duplicate key' not in str(e):
            print(f"Error: {e}")

print(f"Total historical records: {db.historicaldata.count_documents({})}")

# Create products with correct categories/regions
print("Creating products...")
products_data = df.groupby(['Product ID', 'Store ID']).agg({
    'Category': 'first',
    'Region': 'first',
    'Inventory Level': 'last',
    'Price': 'last'
}).reset_index()

products_created = 0
for _, row in products_data.iterrows():
    product = {
        'productId': str(row['Product ID']).upper(),
        'storeId': str(row['Store ID']).upper(),
        'category': str(row['Category']).strip(),
        'region': str(row['Region']).strip(),
        'currentInventory': float(row['Inventory Level']),
        'price': float(row['Price']),
        'lastUpdated': datetime.now()
    }
    
    db.products.update_one(
        {'productId': product['productId'], 'storeId': product['storeId']},
        {'$set': product},
        upsert=True
    )
    products_created += 1

print(f"Created/updated {products_created} products")
print(f"Total products: {db.products.count_documents({})}")

# Verify categories and regions
print("\nCategory distribution:")
categories = db.products.distinct('category')
for cat in categories:
    count = db.products.count_documents({'category': cat})
    print(f"  {cat}: {count}")

print("\nRegion distribution:")
regions = db.products.distinct('region')
for reg in regions:
    count = db.products.count_documents({'region': reg})
    print(f"  {reg}: {count}")

print("\nSample products:")
for product in db.products.find().limit(5):
    print(f"  {product['productId']}/{product['storeId']}: {product['category']} • {product['region']}")

print("\nDone!")
