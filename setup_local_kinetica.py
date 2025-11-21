#!/usr/bin/env python3
"""
Setup script for local Kinetica instance configuration.
This script helps configure the repository to use a local Kinetica instance
instead of the remote demo instance.
"""

import os
import sys
from pathlib import Path

def setup_local_kinetica():
    """Configure the repository to use local Kinetica instance."""
    
    print("🔧 Setting up local Kinetica configuration...")
    
    # Set environment variables for local Kinetica
    os.environ["KINETICA_HOST"] = "localhost:9191"
    os.environ["KINETICA_USERNAME"] = "admin"
    os.environ["KINETICA_PASSWORD"] = "admin"
    os.environ["KINETICA_SCHEMA"] = "nvidia_gtc_dli_2025"
    
    print("✅ Environment variables configured for local Kinetica instance")
    print(f"   Host: {os.environ['KINETICA_HOST']}")
    print(f"   Username: {os.environ['KINETICA_USERNAME']}")
    print(f"   Schema: {os.environ['KINETICA_SCHEMA']}")
    
    print("\n📋 Next steps:")
    print("1. Start the local Kinetica instance:")
    print("   cd llm-slicing-5g-lab")
    print("   ./run_kinetica_headless.sh")
    print("\n2. Access the Kinetica admin console at:")
    print("   http://localhost:8080/gadmin")
    print("\n3. Run the Jupyter notebooks - they will now use the local instance")
    
    print("\n🔗 Local Kinetica access points:")
    print("   - Workbench: http://localhost:8000/workbench")
    print("   - Admin Console: http://localhost:8080/gadmin")
    print("   - Reveal UI: http://localhost:8088")
    print("   - Database REST: http://localhost:9191")
    print("   - Postgres Wire: localhost:5434")

if __name__ == "__main__":
    setup_local_kinetica()
