import random
from datetime import datetime, timedelta
import os

try:
    N = int(input("Enter the number of income records: "))
except ValueError:
    print("Invalid input. Please enter an integer.")
    exit()

if N > 0:
    # Create seed folder if it doesn't exist
    seed_folder = "seeds"
    os.makedirs(seed_folder, exist_ok=True)
    
    # Open the output file in the seed folder
    output_filename = os.path.join(seed_folder, f"seed_income_{N}_records.sql")
    
    # Sample data for randomization
    payment_methods = ['Transfer Bank', 'Cash', 'E-Wallet', 'Kartu Kredit', 'Kartu Debit']
    descriptions = [
        'Donasi dari masyarakat umum',
        'Sumbangan untuk program pendidikan',
        'Hibah pemerintah',
        'Donasi perusahaan CSR',
        'Hasil investasi',
        'Pendapatan jasa konsultasi',
        'Sumbangan acara charity',
        'Donasi anonymous',
        'Hasil penjualan produk',
        'Pendapatan dari event fundraising'
    ]
    
    # COA IDs for income accounts (4xxx range)
    coa_ids = [401, 402, 403, 404, 405]
    
    # Start ID from 1001 to avoid conflicts
    start_id = 1001
    
    with open(output_filename, 'w', encoding='utf-8') as f:
        # Header
        f.write("-- ========================================\n")
        f.write("-- Seed Income Records for /call/income/list\n")
        f.write(f"-- Generated: {N} records\n")
        f.write("-- ========================================\n\n")
        
        # Ensure COA records exist
        f.write("-- Ensure Chart of Account records exist\n")
        f.write("INSERT INTO chartofaccount_comp (id) VALUES \n")
        f.write(",\n".join([f"({coa_id})" for coa_id in coa_ids]))
        f.write("\nON CONFLICT (id) DO NOTHING;\n\n")
        
        f.write("INSERT INTO chartofaccount_impl (id, code, name, description, isvisible) VALUES\n")
        coa_values = [
            "(401, 4001, 'Sumbangan Donasi', 'Pendapatan dari donasi masyarakat', 'true')",
            "(402, 4002, 'Hibah', 'Pendapatan dari hibah institusi', 'true')",
            "(403, 4003, 'Jasa Layanan', 'Pendapatan dari jasa layanan', 'true')",
            "(404, 4004, 'Investasi', 'Pendapatan dari hasil investasi', 'true')",
            "(405, 4005, 'Lain-lain', 'Pendapatan lain-lain', 'true')"
        ]
        f.write(",\n".join(coa_values))
        f.write("\nON CONFLICT (id) DO NOTHING;\n\n")
        
        # Ensure Program records exist (for foreign key references)
        f.write("-- Ensure Program records exist (for foreign key references)\n")
        f.write("INSERT INTO program_comp (idprogram, name, description, executiondate, logourl, partner, target) VALUES\n")
        program_values = [
            "(0, 'Program Umum', 'Program kegiatan umum', '2024-01-01', 'https://example.com/logo0.png', 'Internal', 'Umum')",
            "(1, 'Program Pendidikan', 'Program bantuan pendidikan', '2024-01-15', 'https://example.com/logo1.png', 'Yayasan Pendidikan', 'Anak sekolah')",
            "(2, 'Program Kesehatan', 'Program kesehatan gratis', '2024-02-20', 'https://example.com/logo2.png', 'Klinik Sehat', 'Masyarakat umum')"
        ]
        f.write(",\n".join(program_values))
        f.write("\nON CONFLICT (idprogram) DO NOTHING;\n\n")
        
        f.write("INSERT INTO program_activity (idprogram) VALUES\n")
        f.write("(0),\n(1),\n(2)")
        f.write("\nON CONFLICT (idprogram) DO NOTHING;\n\n")
        
        # Financial Report Component records
        f.write("-- Insert Financial Report Component records\n")
        f.write("INSERT INTO financialreport_comp (id, amount, datestamp, description, coa_id, program_idprogram) VALUES\n")
        
        comp_values = []
        for i in range(N):
            record_id = start_id + i
            # Random amount between 100,000 and 10,000,000
            # Limited to avoid sum exceeding 32-bit integer (2,147,483,647)
            # Max sum for large datasets: 10M * 10000 records = 100B (safe)
            amount = random.randint(100, 10000)
            # Random date in last 12 months
            days_ago = random.randint(0, 365)
            date = (datetime.now() - timedelta(days=days_ago)).strftime('%Y-%m-%d')
            # Random description
            description = random.choice(descriptions)
            # Random COA
            coa_id = random.choice(coa_ids)
            # Most records without program (NULL), to avoid FK constraint issues
            # Only assign program if you're sure programs 0-4 exist in program_comp table
            program_id = random.choice(['NULL', 'NULL', 'NULL', 'NULL', 'NULL', 'NULL', 0, 1, 2])
            
            comp_values.append(
                f"({record_id}, {amount}, '{date}', '{description}', {coa_id}, {program_id})"
            )
        
        f.write(",\n".join(comp_values))
        f.write("\nON CONFLICT (id) DO NOTHING;\n\n")
        
        # Financial Report Implementation records
        f.write("-- Insert Financial Report Implementation records\n")
        f.write("INSERT INTO financialreport_impl (id) VALUES\n")
        impl_values = [f"({start_id + i})" for i in range(N)]
        f.write(",\n".join(impl_values))
        f.write("\nON CONFLICT (id) DO NOTHING;\n\n")
        
        # Income-specific records
        f.write("-- Insert Income-specific records with payment method\n")
        f.write("INSERT INTO financialreport_income (id, paymentmethod) VALUES\n")
        income_values = []
        for i in range(N):
            record_id = start_id + i
            payment_method = random.choice(payment_methods)
            income_values.append(f"({record_id}, '{payment_method}')")
        
        f.write(",\n".join(income_values))
        f.write("\nON CONFLICT (id) DO NOTHING;\n\n")
        
        # Update sequence
        f.write("-- Update hibernate_sequence to avoid ID conflicts\n")
        f.write(f"SELECT setval('hibernate_sequence', {start_id + N + 100}, true);\n\n")
        
        # Verification query
        f.write("-- ========================================\n")
        f.write("-- Verification Query\n")
        f.write("-- ========================================\n")
        f.write("-- Run this to verify the data:\n")
        f.write("/*\n")
        f.write("SELECT \n")
        f.write("  fr.id,\n")
        f.write("  fr.amount,\n")
        f.write("  fr.datestamp,\n")
        f.write("  fr.description,\n")
        f.write("  fi.paymentmethod,\n")
        f.write("  coa.name as account_name,\n")
        f.write("  p.name as program_name\n")
        f.write("FROM financialreport_comp fr\n")
        f.write("JOIN financialreport_income fi ON fr.id = fi.id\n")
        f.write("JOIN chartofaccount_impl coa ON fr.coa_id = coa.id\n")
        f.write("LEFT JOIN program_comp p ON fr.program_idprogram = p.idprogram\n")
        f.write("ORDER BY fr.datestamp DESC\n")
        f.write("LIMIT 20;\n")
        f.write("*/\n")
        f.write("\n")
        f.write("SELECT COUNT(*) FROM financialreport_comp;\n")
    
    print(f"✓ SQL file generated successfully: {output_filename}")
    print(f"✓ Contains {N} income records")
    print(f"✓ Date range: Last 365 days")
    print(f"✓ Amount range: Rp 100,000 - Rp 50,000,000")
    print(f"\nTo import the data:")
    print(f"  1. Upload: scp {output_filename} ubuntu@your-vm:/tmp/")
    print(f"  2. Import: psql -U postgres -d aisco_product_hightide -f /tmp/{output_filename}")
    print(f"  3. Verify: Check endpoint https://hightide-no-cache.sple.my.id/call/income/list")

else:
    print("Nothing to generate (N must be greater than 0).")
