# Inventory_management_system

A ML-powered inventory management system that combines **demand forecasting (60-day horizon)** with **inventory optimization** (safety stock, reorder point, risk alerts) in a **microservices architecture**: offline model training + online real-time inference + dashboard.

> Architecture reference: *Inventory Management System – Modelling Architecture (v1.0, Nov 15, 2025)* :contentReference[oaicite:1]{index=1}

---

## ✨ Key Features

- **60-day demand forecasting** (primary model: **XGBoost Regressor**) with fast inference
- **Real-time inference API** (sub-second response) + iterative multi-step forecasting
- **Inventory optimization metrics**
  - Safety Stock
  - Reorder Point
  - Risk detection: Stockout / Low stock / Overstock
- **Batch forecasting pipeline**: upload CSV → job queue → forecast multiple SKUs/stores → download results
- **Caching & job queue** with Redis
- **Persistence** with MongoDB
- **Role-based access control (RBAC)** + JWT authentication
- Designed for scalability: from ~1,000 to 10,000+ SKUs with horizontal scaling

---

## 🏗 System Architecture Overview

**Frontend (React)** → **Backend API (Express)** → **ML Service (Flask)**  
MongoDB (storage) + Redis (cache + batch job queue)

- Frontend: Port **3000**
- Backend API (Express): Port **5000**
- ML Service (Flask): Port **5001**
- MongoDB: Port **27017**
- Redis: Port **6379** :contentReference[oaicite:2]{index=2}

---

## 🔁 Offline Sub-system (Training & Batch Processing)

Runs periodically (daily/weekly) to retrain models and generate batch forecasts.

### Primary Forecast Model: XGBoost Regressor
- Forecast horizon: **next 60 days**
- Selected due to best benchmark results:
  - **MAE ~12.3**
  - **R² ~0.87**
  - **Inference ~0.05s** :contentReference[oaicite:3]{index=3}

### Input Features (high-level)
- Product attributes: `product_id`, `category`, `price`
- Store attributes: `store_id`, `region`
- Temporal features: `month`, `day`, `week`, `year`
- Lag features: `lag_1`, `lag_7`, `lag_30`
- Rolling stats: `rolling_mean_7`, `rolling_std_7`, `rolling_mean_30`, `rolling_std_30`
- Promotion: `discount` :contentReference[oaicite:4]{index=4}

### Preprocessing Pipeline (7 steps)
1. Date handling (datetime, sort)
2. One-hot encoding (category/region/store_id)
3. MinMax scaling (0–1)
4. Feature engineering (lags, rolling)
5. Outlier removal (IQR 1.5x)
6. Missing handling (ffill + bfill)
7. Train/test split 80/20 (no shuffle) :contentReference[oaicite:5]{index=5}

### Alternative Models (for experiments)
- LSTM, N-BEATS, TCN, Prophet (not primary) :contentReference[oaicite:6]{index=6}

### Batch Forecasting Flow
1. User uploads CSV (example scale: 73k+ rows)
2. Validate schema & completeness
3. Create `job_id`, enqueue to Redis
4. Process each product (seq/parallel)
5. Generate 60-day forecast per product-store
6. Compute optimization metrics
7. Store results in MongoDB (with `job_id`)
8. Return completed status + download link :contentReference[oaicite:7]{index=7}

---

## ⚡ Online Sub-system (Real-time Inference & Optimization)

### Real-time Forecast API
**Endpoint**
- `POST /api/ml/predict/realtime`

**Example request**
```json
{
  "product_id": "P0001",
  "store_id": "S001",
  "current_inventory": 150,
  "current_date": "2024-06-15",
  "historical_data": []
}
