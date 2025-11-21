#!/usr/bin/env python3
"""
Diagnostic script to check Kinetica connection and table status
"""
import os
import sys

print("=" * 60)
print("🔍 KINETICA DIAGNOSTIC CHECK")
print("=" * 60)

# Step 1: Check if Kinetica Python package is installed
print("\n1️⃣ Checking Kinetica Python package...")
try:
    from gpudb import GPUdb, GPUdbTable
    from gpudb import GPUdbColumnProperty as cp
    from gpudb import GPUdbRecordColumn as rc

    print("   ✅ Kinetica Python package installed")
except ImportError as e:
    print(f"   ❌ Kinetica Python package not installed: {e}")
    print("   Run: pip install gpudb")
    sys.exit(1)

# Step 2: Try to connect to Kinetica
print("\n2️⃣ Connecting to Kinetica...")
try:
    kdbc_options = GPUdb.Options()
    kdbc_options.username = "admin"
    kdbc_options.password = "Admin123!"
    kdbc_options.disable_auto_discovery = True
    kdbc = GPUdb(host="localhost:9191", options=kdbc_options)
    print("   ✅ Connected to Kinetica at localhost:9191")
except Exception as e:
    print(f"   ❌ Failed to connect to Kinetica: {e}")
    print("   Make sure Kinetica is running:")
    print("   - Check: docker ps | grep kinetica")
    print("   - Start: ./run_kinetica_headless.sh")
    sys.exit(1)

# Step 3: Check schema
print("\n3️⃣ Checking schema...")
target_schema = "nvidia_gtc_dli_2025"
try:
    result = kdbc.show_schema(schema_name=target_schema)
    if result["schema_names"]:
        print(f"   ✅ Schema '{target_schema}' exists")
    else:
        print(f"   ⚠️  Schema '{target_schema}' does not exist")
        print(f"   Creating schema...")
        kdbc.create_schema(schema_name=target_schema)
        print(f"   ✅ Schema '{target_schema}' created")
except Exception as e:
    print(f"   ⚠️  Error checking schema: {e}")
    # Try to create it anyway
    try:
        kdbc.create_schema(schema_name=target_schema)
        print(f"   ✅ Schema '{target_schema}' created")
    except Exception as e2:
        if "already exists" in str(e2).lower():
            print(f"   ✅ Schema '{target_schema}' already exists")
        else:
            print(f"   ❌ Failed to create schema: {e2}")

# Step 4: Check table
print("\n4️⃣ Checking table...")
FIXED_TABLE_NAME = "nvidia_gtc_dli_2025.iperf3_logs"
try:
    table_exists = kdbc.has_table(table_name=FIXED_TABLE_NAME)["table_exists"]
    if table_exists:
        print(f"   ✅ Table '{FIXED_TABLE_NAME}' exists")

        # Get row count
        try:
            result = kdbc.execute_sql(f"SELECT COUNT(*) FROM {FIXED_TABLE_NAME}")
            count = result["data"][0][0] if result["data"] else 0
            print(f"   📊 Table has {count} records")
        except Exception as e:
            print(f"   ⚠️  Could not get row count: {e}")
    else:
        print(f"   ⚠️  Table '{FIXED_TABLE_NAME}' does not exist")
        print(f"   Creating table...")

        schema = [
            ["id", rc._ColumnType.STRING, cp.UUID, cp.PRIMARY_KEY, cp.INIT_WITH_UUID],
            ["ue", rc._ColumnType.STRING, cp.CHAR8, cp.DICT],
            ["timestamp", rc._ColumnType.STRING, cp.DATETIME, cp.INIT_WITH_NOW],
            ["stream", rc._ColumnType.INT, cp.INT8, cp.DICT],
            ["interval_start", rc._ColumnType.FLOAT],
            ["interval_end", rc._ColumnType.FLOAT],
            ["duration", rc._ColumnType.FLOAT],
            ["data_transferred", rc._ColumnType.FLOAT],
            ["bitrate", rc._ColumnType.FLOAT],
            ["jitter", rc._ColumnType.FLOAT],
            ["lost_packets", rc._ColumnType.INT],
            ["total_packets", rc._ColumnType.INT],
            ["loss_percentage", rc._ColumnType.FLOAT],
        ]
        kdbc_table = GPUdbTable(_type=schema, name=FIXED_TABLE_NAME, db=kdbc)
        print(f"   ✅ Table '{FIXED_TABLE_NAME}' created successfully")

except Exception as e:
    print(f"   ❌ Error with table: {e}")
    import traceback

    traceback.print_exc()
    sys.exit(1)

# Step 5: Test insert
print("\n5️⃣ Testing insert...")
try:
    test_sql = f"""INSERT INTO {FIXED_TABLE_NAME} 
                   ("ue", "stream", "interval_start", "interval_end", "data_transferred", 
                    "bitrate", "jitter", "lost_packets", "total_packets", "loss_percentage", "duration")
                   VALUES ('TEST', 1, 0.0, 1.0, 10.0, 80.0, 0.5, 0, 100, 0.0, 1.0)"""
    kdbc.execute_sql(test_sql)
    print("   ✅ Test insert successful")

    # Clean up test record
    kdbc.execute_sql(f"DELETE FROM {FIXED_TABLE_NAME} WHERE ue = 'TEST'")
    print("   ✅ Test record cleaned up")

except Exception as e:
    print(f"   ❌ Test insert failed: {e}")
    import traceback

    traceback.print_exc()

print("\n" + "=" * 60)
print("✅ KINETICA DIAGNOSTIC COMPLETE")
print("=" * 60)
print(f"\n📋 Summary:")
print(f"   - Kinetica URL: http://localhost:8080/gadmin")
print(f"   - Schema: {target_schema}")
print(f"   - Table: {FIXED_TABLE_NAME}")
print(f"   - Username: admin")
print(f"   - Password: Admin123!")
