"""FastAPI backend."""

from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

app = FastAPI(
    title="dev-openclaw Backend",
    version="0.3.0",
)
app.openapi_version = "3.0.3"


@app.get("/health")
def health():
    return {"status": "ok"}
