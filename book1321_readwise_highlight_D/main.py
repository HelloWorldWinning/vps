from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import pandas as pd
import json

app = FastAPI()

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

# Setup templates
templates = Jinja2Templates(directory="templates")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load CSV data
def load_data():
    data_dir = Path("data")
    all_data = []

    # Read all CSV files in the data directory
    for csv_file in data_dir.glob("*.csv"):
        try:
            df = pd.read_csv(csv_file)

            # Clean column headers: remove spaces and make lowercase
            df.columns = [col.replace(' ', '').lower() for col in df.columns]

            all_data.append(df)
        except Exception as e:
            print(f"Error reading {csv_file}: {e}")

    # Combine all dataframes
    if all_data:
        combined_df = pd.concat(all_data, ignore_index=True)
        return combined_df
    return pd.DataFrame()

# Load data at startup
highlights_df = load_data()

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

# Serve favicon
@app.get('/favicon.ico', include_in_schema=False)
async def favicon():
    return FileResponse('static/favicon.ico')

@app.get("/api/highlights")
async def get_highlights():
    if highlights_df.empty:
        raise HTTPException(status_code=404, detail="No data found")

    # Convert DataFrame to dict and handle NaN values
    highlights_list = json.loads(highlights_df.fillna('').to_json(orient='records'))
    return highlights_list

@app.get("/api/filters")
async def get_filters():
    if highlights_df.empty:
        raise HTTPException(status_code=404, detail="No data found")

    # Function to safely get unique sorted values
    def get_unique_sorted_values(column):
        # Convert to string, handle NaN/None, remove empty strings, and sort
        values = highlights_df[column].dropna().astype(str)
        values = [v for v in values.unique() if v.strip()]
        return sorted(values)

    # Get unique values for each filter
    filters = {
        "bookTitles": get_unique_sorted_values('booktitle'),
        "bookAuthors": get_unique_sorted_values('bookauthor'),
        "colors": get_unique_sorted_values('color'),
        "tags": sorted(list(set([
            tag.strip()
            for tags in highlights_df['tags'].dropna()
            for tag in str(tags).split(',')
            if tag.strip()
        ])))
    }

    return filters

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

