# Kinetica Configuration Update: Switching to Local Instance

## Overview
Successfully updated the repository configuration to use a local Kinetica instance instead of the remote demo instance at `demo72.kinetica.com`. All Jupyter notebooks and agentic-llm files now point to the local instance that runs with `run_kinetica_headless.sh`.

## Changes Made

### 1. Updated Jupyter Notebooks
**File: `llm-slicing-5g-lab/DLI_Lab_Setup.ipynb`**
- Modified the Kinetica connection configuration to use local environment variables
- Changed from `load_dotenv()` to direct environment variable setting
- Updated Kinetica admin console URL from `https://demo72.kinetica.com/gadmin/` to `http://localhost:8080/gadmin/`
- Updated credentials in documentation to reflect local instance settings

### 2. Updated Agentic-LLM Files
**File: `agentic-llm/tools.py`**
- Replaced `load_dotenv("../llm-slicing-5g-lab/.env")` with direct environment variable configuration
- Set local Kinetica connection parameters

**File: `agentic-llm/chatbot_DLI.py`**
- Updated Kinetica connection configuration to use local instance
- Removed dependency on .env file loading in `generate_sql_query()` function

### 3. Updated Documentation
**File: `README.md`**
- Updated Kinetica access instructions to reference local instance
- Changed credentials and URL references to local configuration

### 4. Created Setup Script
**File: `setup_local_kinetica.py`**
- Created a helper script to configure environment variables for local Kinetica
- Provides clear instructions for starting the local instance
- Lists all local Kinetica access points

## Local Kinetica Configuration

### Connection Details
- **Host**: `localhost:9191`
- **Username**: `admin`
- **Password**: `Admin123!`
- **Schema**: `nvidia_gtc_dli_2025`

### Access Points
- **Workbench**: http://localhost:8000/workbench
- **Admin Console**: http://localhost:8080/gadmin
- **Reveal UI**: http://localhost:8088
- **Database REST**: http://localhost:9191
- **Postgres Wire**: localhost:5434

## Usage Instructions

### 1. Start Local Kinetica Instance
```bash
cd llm-slicing-5g-lab
./run_kinetica_headless.sh
```

### 2. Run Jupyter Notebooks
The notebooks will now automatically connect to the local Kinetica instance. No additional configuration is needed.

### 3. Access Kinetica Admin Console
Open http://localhost:8080/gadmin in your browser and login with:
- Username: `admin`
- Password: `Admin123!`

## Benefits of Local Configuration

1. **No Internet Dependency**: The lab can run completely offline
2. **Faster Performance**: Local database access is faster than remote connections
3. **Data Persistence**: Data is stored locally in the `kinetica-data` directory
4. **Full Control**: Complete control over the database instance and configuration
5. **Development Friendly**: Easier to debug and modify database settings

## Files Modified
- `llm-slicing-5g-lab/DLI_Lab_Setup.ipynb`
- `agentic-llm/tools.py`
- `agentic-llm/chatbot_DLI.py`
- `README.md`
- `setup_local_kinetica.py` (new file)

## Verification
All references to the remote Kinetica instance (`demo72.kinetica.com`) have been replaced with local configuration. The notebooks and agentic files are now configured to use the local instance that runs with the provided `run_kinetica_headless.sh` script.

The configuration is now ready for use with the local Kinetica instance. Simply start the local instance using the provided script and run the Jupyter notebooks as usual.
