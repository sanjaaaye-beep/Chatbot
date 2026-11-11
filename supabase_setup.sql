-- Run this in Supabase SQL Editor after creating the products table.
-- Stores the result of each inventory analysis request.
create table if not exists public.ai_inventory_analysis_results (
    analysis_id uuid primary key default gen_random_uuid(),
    product_id uuid references public.products(product_id) on delete set null,
    request_id text,
    requested_quantity integer not null check (requested_quantity > 0),
    current_stock integer,
    shortage_quantity integer,
    stock_sufficient boolean,
    recommended_reorder_quantity integer not null default 0,
    result_status text not null,
    analysis jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_inventory_analysis_product
    on public.ai_inventory_analysis_results(product_id);
create index if not exists idx_inventory_analysis_created
    on public.ai_inventory_analysis_results(created_at desc);

-- IMPORTANT:
-- Keep this table private. Do not enable unrestricted anon access.
-- The n8n workflow uses the Supabase service-role key server-side.
alter table public.ai_inventory_analysis_results enable row level security;
