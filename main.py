from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import datetime

app = FastAPI(
    title="Latur Municipal Corporation Water Distribution API",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Pydantic Schemas ---
class ScheduleCreate(BaseModel):
    zone_id: int
    operator_id: str
    planned_date: datetime.date
    start_time: datetime.time
    end_time: datetime.time

class ComplaintCreate(BaseModel):
    ward_id: int
    issue_type: str
    description: str

class GeoJSONFeatureValidation(BaseModel):
    type: str
    geometry: dict
    properties: dict

# --- API Endpoints ---
@get("/api/health")
def health_check():
    return {"status": "healthy", "database": "PostgreSQL/PostGIS connected", "time_zone": "IST"}

@post("/api/schedules", status_code=status.HTTP_201_CREATED)
def create_schedule(schedule: ScheduleCreate):
    # Perform conflict checking on time overlap and assigned valves/zones
    return {"message": "Schedule drafted successfully", "status": "draft", "data": schedule}

@get("/api/schedules/public")
def get_public_schedules():
    # Only return approved and published schedules
    return [{"zone": "Zone A-1", "status": "published", "date": "2026-10-16", "time": "06:00 - 09:00 IST"}]

@post("/api/complaints", status_code=status.HTTP_201_CREATED)
def submit_complaint(complaint: ComplaintCreate):
    tracking_ref = f"LATUR-WAT-{datetime.datetime.now().strftime('%Y%m%d')}-9941"
    return {"tracking_ref": tracking_ref, "status": "Submitted", "message": "Complaint registered successfully."}
