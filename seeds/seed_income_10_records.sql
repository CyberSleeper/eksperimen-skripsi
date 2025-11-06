-- ========================================
-- Seed Income Records for /call/income/list
-- Generated: 10 records
-- ========================================

-- Ensure Chart of Account records exist
INSERT INTO chartofaccount_comp (id) VALUES 
(401),
(402),
(403),
(404),
(405)
ON CONFLICT (id) DO NOTHING;

INSERT INTO chartofaccount_impl (id, code, name, description, isvisible) VALUES
(401, 4001, 'Sumbangan Donasi', 'Pendapatan dari donasi masyarakat', 'true'),
(402, 4002, 'Hibah', 'Pendapatan dari hibah institusi', 'true'),
(403, 4003, 'Jasa Layanan', 'Pendapatan dari jasa layanan', 'true'),
(404, 4004, 'Investasi', 'Pendapatan dari hasil investasi', 'true'),
(405, 4005, 'Lain-lain', 'Pendapatan lain-lain', 'true')
ON CONFLICT (id) DO NOTHING;

-- Ensure Program records exist (for foreign key references)
INSERT INTO program_comp (idprogram, name, description, executiondate, logourl, partner, target) VALUES
(0, 'Program Umum', 'Program kegiatan umum', '2024-01-01', 'https://example.com/logo0.png', 'Internal', 'Umum'),
(1, 'Program Pendidikan', 'Program bantuan pendidikan', '2024-01-15', 'https://example.com/logo1.png', 'Yayasan Pendidikan', 'Anak sekolah'),
(2, 'Program Kesehatan', 'Program kesehatan gratis', '2024-02-20', 'https://example.com/logo2.png', 'Klinik Sehat', 'Masyarakat umum')
ON CONFLICT (idprogram) DO NOTHING;

INSERT INTO program_activity (idprogram) VALUES
(0),
(1),
(2)
ON CONFLICT (idprogram) DO NOTHING;

-- Insert Financial Report Component records
INSERT INTO financialreport_comp (id, amount, datestamp, description, coa_id, program_idprogram) VALUES
(1001, 649606, '2024-12-09', 'Hibah pemerintah', 405, NULL),
(1002, 571967, '2025-08-22', 'Donasi anonymous', 402, NULL),
(1003, 590180, '2025-03-02', 'Donasi anonymous', 404, NULL),
(1004, 576760, '2024-11-18', 'Sumbangan acara charity', 405, NULL),
(1005, 242034, '2025-09-02', 'Donasi anonymous', 401, NULL),
(1006, 342427, '2024-11-20', 'Sumbangan untuk program pendidikan', 404, 0),
(1007, 550556, '2024-12-07', 'Donasi perusahaan CSR', 405, NULL),
(1008, 339169, '2025-04-04', 'Sumbangan acara charity', 404, NULL),
(1009, 237102, '2025-06-13', 'Hasil investasi', 404, NULL),
(1010, 161877, '2024-11-15', 'Donasi perusahaan CSR', 405, 1)
ON CONFLICT (id) DO NOTHING;

-- Insert Financial Report Implementation records
INSERT INTO financialreport_impl (id) VALUES
(1001),
(1002),
(1003),
(1004),
(1005),
(1006),
(1007),
(1008),
(1009),
(1010)
ON CONFLICT (id) DO NOTHING;

-- Insert Income-specific records with payment method
INSERT INTO financialreport_income (id, paymentmethod) VALUES
(1001, 'Cash'),
(1002, 'Transfer Bank'),
(1003, 'Cash'),
(1004, 'Kartu Debit'),
(1005, 'E-Wallet'),
(1006, 'Kartu Kredit'),
(1007, 'Transfer Bank'),
(1008, 'Transfer Bank'),
(1009, 'Transfer Bank'),
(1010, 'Transfer Bank')
ON CONFLICT (id) DO NOTHING;

-- Update hibernate_sequence to avoid ID conflicts
SELECT setval('hibernate_sequence', 1111, true);

-- ========================================
-- Verification Query
-- ========================================
-- Run this to verify the data:
/*
SELECT 
  fr.id,
  fr.amount,
  fr.datestamp,
  fr.description,
  fi.paymentmethod,
  coa.name as account_name,
  p.name as program_name
FROM financialreport_comp fr
JOIN financialreport_income fi ON fr.id = fi.id
JOIN chartofaccount_impl coa ON fr.coa_id = coa.id
LEFT JOIN program_comp p ON fr.program_idprogram = p.idprogram
ORDER BY fr.datestamp DESC
LIMIT 20;
*/
