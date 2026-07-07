-- ============================================================
-- Migration: tambah kolom is_admin ke tabel people
-- Untuk fitur "Admin Gudang" (staff yang boleh tambah/edit/hapus barang)
-- Jalankan sekali di Supabase → SQL Editor
-- ============================================================

ALTER TABLE people ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;

-- (Opsional) Langsung jadikan akun tertentu sebagai Admin Gudang.
-- Ganti nama sesuai akun yang Anda buat, lalu hapus tanda komentar (--).
-- UPDATE people SET is_admin = true WHERE name = 'SJA-ADMIN';
-- UPDATE people SET is_admin = true WHERE name = 'DIN-ADMIN';
-- UPDATE people SET is_admin = true WHERE name = 'OLENTIA-ADMIN';

-- Cek hasil:
-- SELECT name, warehouses, is_admin FROM people ORDER BY name;
