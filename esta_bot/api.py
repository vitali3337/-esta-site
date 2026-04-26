from fastapi import FastAPI, HTTPException, Query, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
import asyncpg
import os
import uuid

RATES_TO_USD = {"USD": 1.0, "EUR": 1.08, "MDL": 0.056, "RUB": 0.011}

app = FastAPI(title="ESTA API", description="AI Real Estate Platform · Moldova & Transnistria", version="1.0.0")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

async def get_db():
    conn = await asyncpg.connect(os.getenv("DATABASE_URL"))
    try:
        yield conn
    finally:
        await conn.close()

class PropertyCreate(BaseModel):
    deal_type: str = Field(..., pattern="^(sale|rent)$")
    property_type: str = Field(..., pattern="^(apartment|house|commercial|garage|storage|land)$")
    is_new_build: bool = False
    city_id: int
    district: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    rooms: Optional[int] = None
    floor: Optional[int] = None
    floors_total: Optional[int] = None
    area_total: Optional[float] = None
    area_living: Optional[float] = None
    area_kitchen: Optional[float] = None
    price: float
    currency: str = Field("USD", pattern="^(USD|EUR|MDL|RUB)$")
    title: Optional[str] = None
    description: Optional[str] = None
    photos: Optional[List[str]] = []
    contact_name: Optional[str] = None
    contact_phone: Optional[str] = None
    contact_type: str = "owner"
    source: str = "manual"
    source_url: Optional[str] = None
    external_id: Optional[str] = None

class PropertyUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    currency: Optional[str] = None
    is_active: Optional[bool] = None
    is_featured: Optional[bool] = None
    photos: Optional[List[str]] = None
    address: Optional[str] = None

def to_usd(price: float, currency: str) -> float:
    return round(price * RATES_TO_USD.get(currency, 1.0), 2)

@app.get("/")
async def root():
    return {"platform": "ESTA", "version": "1.0.0", "market": "Moldova & Transnistria"}

@app.post("/properties")
async def create_property(data: PropertyCreate, db=Depends(get_db)):
    price_usd = to_usd(data.price, data.currency)
    row = await db.fetchrow("""
        INSERT INTO properties (
          deal_type, property_type, is_new_build, city_id, district, address,
          lat, lng, rooms, floor, floors_total, area_total, area_living, area_kitchen,
          price, currency, price_usd, title, description, photos,
          contact_name, contact_phone, contact_type, source, source_url, external_id
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26)
        RETURNING id, created_at
    """, data.deal_type, data.property_type, data.is_new_build,
        data.city_id, data.district, data.address,
        data.lat, data.lng, data.rooms, data.floor, data.floors_total,
        data.area_total, data.area_living, data.area_kitchen,
        data.price, data.currency, price_usd,
        data.title, data.description, data.photos or [],
        data.contact_name, data.contact_phone, data.contact_type,
        data.source, data.source_url, data.external_id)
    return {"id": str(row["id"]), "created_at": row["created_at"], "status": "created"}

@app.get("/properties")
async def list_properties(
    city_id: Optional[int] = None, deal_type: Optional[str] = None,
    property_type: Optional[str] = None, rooms: Optional[int] = None,
    price_min: Optional[float] = None, price_max: Optional[float] = None,
    is_new_build: Optional[bool] = None, is_featured: Optional[bool] = None,
    q: Optional[str] = None, limit: int = Query(20, le=100), offset: int = 0,
    db=Depends(get_db)):
    conditions = ["is_active = TRUE"]
    params = []
    i = 1
    if city_id: conditions.append(f"city_id = ${i}"); params.append(city_id); i+=1
    if deal_type: conditions.append(f"deal_type = ${i}"); params.append(deal_type); i+=1
    if property_type: conditions.append(f"property_type = ${i}"); params.append(property_type); i+=1
    if rooms is not None: conditions.append(f"rooms = ${i}"); params.append(rooms); i+=1
    if price_min is not None: conditions.append(f"price_usd >= ${i}"); params.append(price_min); i+=1
    if price_max is not None: conditions.append(f"price_usd <= ${i}"); params.append(price_max); i+=1
    if is_new_build is not None: conditions.append(f"is_new_build = ${i}"); params.append(is_new_build); i+=1
    if is_featured is not None: conditions.append(f"is_featured = ${i}"); params.append(is_featured); i+=1
    if q: conditions.append(f"to_tsvector('russian', COALESCE(title,'') || ' ' || COALESCE(description,'')) @@ plainto_tsquery('russian', ${i})"); params.append(q); i+=1
    where = " AND ".join(conditions)
    rows = await db.fetch(f"SELECT p.*, c.name_ru as city_name FROM properties p LEFT JOIN cities c ON p.city_id = c.id WHERE {where} ORDER BY is_featured DESC, created_at DESC LIMIT ${i} OFFSET ${i+1}", *params, limit, offset)
    count = await db.fetchval(f"SELECT COUNT(*) FROM properties WHERE {where}", *params)
    return {"total": count, "limit": limit, "offset": offset, "items": [dict(r) for r in rows]}

@app.get("/properties/{property_id}")
async def get_property(property_id: str, db=Depends(get_db)):
    row = await db.fetchrow("SELECT p.*, c.name_ru as city_name, c.region FROM properties p LEFT JOIN cities c ON p.city_id = c.id WHERE p.id = $1", uuid.UUID(property_id))
    if not row: raise HTTPException(404, "Объект не найден")
    await db.execute("UPDATE properties SET views_count = views_count + 1 WHERE id = $1", uuid.UUID(property_id))
    return dict(row)

@app.patch("/properties/{property_id}")
async def update_property(property_id: str, data: PropertyUpdate, db=Depends(get_db)):
    updates = {k: v for k, v in data.dict(exclude_none=True).items()}
    if not updates: raise HTTPException(400, "Нет данных для обновления")
    if "price" in updates: updates["price_usd"] = to_usd(updates["price"], updates.get("currency", "USD"))
    set_clause = ", ".join([f"{k} = ${i+2}" for i, k in enumerate(updates)])
    result = await db.execute(f"UPDATE properties SET {set_clause} WHERE id = $1", uuid.UUID(property_id), *list(updates.values()))
    if result == "UPDATE 0": raise HTTPException(404, "Объект не найден")
    return {"status": "updated", "id": property_id}

@app.delete("/properties/{property_id}")
async def delete_property(property_id: str, db=Depends(get_db)):
    result = await db.execute("UPDATE properties SET is_active = FALSE WHERE id = $1", uuid.UUID(property_id))
    if result == "UPDATE 0": raise HTTPException(404, "Объект не найден")
    return {"status": "deactivated", "id": property_id}

@app.get("/cities")
async def get_cities(db=Depends(get_db)):
    rows = await db.fetch("SELECT * FROM cities ORDER BY region, name_ru")
    return [dict(r) for r in rows]

@app.get("/stats")
async def get_stats(db=Depends(get_db)):
    row = await db.fetchrow("SELECT * FROM v_stats")
    cities = await db.fetch("SELECT c.name_ru, COUNT(*) as count FROM properties p JOIN cities c ON p.city_id = c.id WHERE p.is_active GROUP BY c.name_ru ORDER BY count DESC")
    return {**dict(row), "by_city": [dict(r) for r in cities]}

@app.post("/leads")
async def create_lead(property_id: Optional[str] = None, telegram_id: Optional[int] = None, name: Optional[str] = None, phone: Optional[str] = None, message: Optional[str] = None, intent: str = "buy", db=Depends(get_db)):
    row = await db.fetchrow("INSERT INTO leads (property_id, telegram_id, name, phone, message, intent) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id", uuid.UUID(property_id) if property_id else None, telegram_id, name, phone, message, intent)
    return {"id": row["id"], "status": "created"}

@app.get("/leads")
async def get_leads(status: Optional[str] = None, limit: int = 50, db=Depends(get_db)):
    where = f"WHERE status = '{status}'" if status else ""
    rows = await db.fetch(f"SELECT * FROM leads {where} ORDER BY created_at DESC LIMIT $1", limit)
    return [dict(r) for r in rows]
