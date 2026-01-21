const fs = require('fs');
const csv = require('csv-parser');
const mongoose = require('mongoose');

// Connect to MongoDB
mongoose.connect('mongodb://localhost:27017/inventory_db');

// Define schemas
const historicalDataSchema = new mongoose.Schema({
  date: Date,
  storeId: String,
  productId: String,
  category: String,
  region: String,
  unitsSold: Number,
  inventoryLevel: Number,
  demandForecast: Number,
  price: Number,
  discount: Number,
  weatherCondition: String,
  seasonality: String,
  uploadedAt: { type: Date, default: Date.now }
});

const productSchema = new mongoose.Schema({
  productId: String,
  storeId: String,
  category: String,
  region: String,
  currentInventory: Number,
  price: Number,
  lastUpdated: { type: Date, default: Date.now }
});

const HistoricalData = mongoose.model('HistoricalData', historicalDataSchema);
const Product = mongoose.model('Product', productSchema);

async function uploadData() {
  const results = [];
  
  // Read CSV
  fs.createReadStream('retail_store_inventory.csv')
    .pipe(csv())
    .on('data', (data) => {
      results.push({
        date: new Date(data.Date),
        storeId: data['Store ID'].toUpperCase(),
        productId: data['Product ID'].toUpperCase(),
        category: data.Category?.trim() || 'Other',
        region: data.Region?.trim() || 'Central',
        unitsSold: parseFloat(data['Units Sold']) || 0,
        inventoryLevel: parseFloat(data['Inventory Level']) || 0,
        demandForecast: parseFloat(data['Demand Forecast']) || null,
        price: parseFloat(data.Price) || 0,
        discount: parseFloat(data['Discount']) || 0,
        weatherCondition: data['Weather Condition']?.trim() || 'Clear',
        seasonality: data.Seasonality?.trim() || 'Regular'
      });
    })
    .on('end', async () => {
      console.log(`Read ${results.length} rows from CSV`);
      
      // Insert historical data in batches
      const batchSize = 1000;
      for (let i = 0; i < results.length; i += batchSize) {
        const batch = results.slice(i, i + batchSize);
        try {
          await HistoricalData.insertMany(batch, { ordered: false });
          console.log(`Inserted batch ${Math.floor(i/batchSize) + 1}`);
        } catch (err) {
          if (err.code !== 11000) console.error('Insert error:', err.message);
        }
      }
      
      console.log('Historical data uploaded');
      
      // Create products with categories/regions
      const productMap = new Map();
      
      results.forEach(row => {
        const key = `${row.productId}_${row.storeId}`;
        if (!productMap.has(key)) {
          productMap.set(key, {
            productId: row.productId,
            storeId: row.storeId,
            category: row.category,
            region: row.region,
            currentInventory: row.inventoryLevel,
            price: row.price
          });
        }
      });
      
      // Insert products
      for (const [key, product] of productMap) {
        await Product.findOneAndUpdate(
          { productId: product.productId, storeId: product.storeId },
          product,
          { upsert: true, new: true }
        );
      }
      
      console.log(`Created ${productMap.size} products`);
      console.log('Done!');
      process.exit(0);
    });
}

uploadData().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
