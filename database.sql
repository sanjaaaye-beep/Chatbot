-- LaptopCare Enterprise Automation Database
-- PostgreSQL / Supabase SQL
-- Run in Supabase SQL Editor.
-- NOTE: Review RLS policies and connect Supabase Auth before production use.

create extension if not exists pgcrypto;

-- 1. Suppliers
create table if not exists public.suppliers (
    supplier_id uuid primary key default gen_random_uuid(),
    supplier_name varchar(150) not null,
    email varchar(150) unique,
    phone varchar(30),
    company_name varchar(150),
    address text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 2. Products
create table if not exists public.products (
    product_id uuid primary key default gen_random_uuid(),
    product_name varchar(150) not null,
    brand varchar(100),
    model varchar(100),
    description text,
    price numeric(12,2) not null check (price >= 0),
    stock_quantity integer not null default 0 check (stock_quantity >= 0),
    warranty_months integer not null default 0 check (warranty_months >= 0),
    primary_supplier_id uuid references public.suppliers(supplier_id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 3. Customers
create table if not exists public.customers (
    customer_id uuid primary key default gen_random_uuid(),
    full_name varchar(150) not null,
    email varchar(150) unique not null,
    phone varchar(30),
    address text,
    city varchar(100),
    state varchar(100),
    postal_code varchar(20),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 4. Orders
create table if not exists public.orders (
    order_id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references public.customers(customer_id) on delete restrict,
    order_date timestamptz not null default now(),
    total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
    order_status varchar(30) not null default 'pending'
        check (order_status in ('pending','confirmed','processing','shipped','delivered','cancelled')),
    payment_status varchar(30) not null default 'unpaid'
        check (payment_status in ('unpaid','paid','refunded','failed')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 5. Order items: resolves the many-to-many relationship between orders and products
create table if not exists public.order_items (
    order_item_id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(order_id) on delete cascade,
    product_id uuid not null references public.products(product_id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price numeric(12,2) not null check (unit_price >= 0),
    subtotal numeric(14,2) generated always as (quantity * unit_price) stored,
    created_at timestamptz not null default now()
);

-- 6. Supplier products: resolves the many-to-many relationship between suppliers and products
create table if not exists public.supplier_products (
    supplier_product_id uuid primary key default gen_random_uuid(),
    supplier_id uuid not null references public.suppliers(supplier_id) on delete cascade,
    product_id uuid not null references public.products(product_id) on delete cascade,
    supply_price numeric(12,2) check (supply_price is null or supply_price >= 0),
    created_at timestamptz not null default now(),
    unique (supplier_id, product_id)
);

-- 7. Shipments
create table if not exists public.shipments (
    shipment_id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(order_id) on delete cascade,
    tracking_number varchar(100) unique,
    courier_name varchar(100),
    shipment_status varchar(30) not null default 'preparing'
        check (shipment_status in ('preparing','dispatched','in_transit','out_for_delivery','delivered','returned')),
    shipping_address text,
    shipped_at timestamptz,
    estimated_delivery timestamptz,
    delivered_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 8. AI agent activity logs
create table if not exists public.ai_agent_logs (
    log_id uuid primary key default gen_random_uuid(),
    customer_id uuid references public.customers(customer_id) on delete set null,
    order_id uuid references public.orders(order_id) on delete set null,
    product_id uuid references public.products(product_id) on delete set null,
    agent_name varchar(100) not null,
    action varchar(150) not null,
    input_data jsonb not null default '{}'::jsonb,
    output_data jsonb not null default '{}'::jsonb,
    execution_status varchar(30) not null default 'success'
        check (execution_status in ('success','failed','pending','escalated')),
    error_message text,
    response_time_ms integer check (response_time_ms is null or response_time_ms >= 0),
    created_at timestamptz not null default now()
);

-- Reusable updated_at trigger
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_suppliers_updated_at on public.suppliers;
create trigger trg_suppliers_updated_at before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists trg_customers_updated_at on public.customers;
create trigger trg_customers_updated_at before update on public.customers
for each row execute function public.set_updated_at();

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at before update on public.orders
for each row execute function public.set_updated_at();

drop trigger if exists trg_shipments_updated_at on public.shipments;
create trigger trg_shipments_updated_at before update on public.shipments
for each row execute function public.set_updated_at();

-- Indexes for common lookups and joins
create index if not exists idx_products_brand on public.products(brand);
create index if not exists idx_products_stock on public.products(stock_quantity);
create index if not exists idx_orders_customer on public.orders(customer_id);
create index if not exists idx_orders_status on public.orders(order_status);
create index if not exists idx_orders_date on public.orders(order_date desc);
create index if not exists idx_order_items_order on public.order_items(order_id);
create index if not exists idx_order_items_product on public.order_items(product_id);
create index if not exists idx_supplier_products_supplier on public.supplier_products(supplier_id);
create index if not exists idx_supplier_products_product on public.supplier_products(product_id);
create index if not exists idx_shipments_order on public.shipments(order_id);
create index if not exists idx_shipments_status on public.shipments(shipment_status);
create index if not exists idx_ai_logs_customer on public.ai_agent_logs(customer_id);
create index if not exists idx_ai_logs_created on public.ai_agent_logs(created_at desc);
create index if not exists idx_ai_logs_status on public.ai_agent_logs(execution_status);


-- Inventory operations extension. Additive migration: existing product, order,
-- supplier, and customer records are retained.
alter table public.products
    add column if not exists sku text,
    add column if not exists category text not null default 'Uncategorized',
    add column if not exists unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
    add column if not exists reorder_point integer not null default 0 check (reorder_point >= 0),
    add column if not exists is_active boolean not null default true;

create unique index if not exists idx_products_sku_unique
    on public.products(sku) where sku is not null;
create index if not exists idx_products_category_active
    on public.products(category, is_active);

create table if not exists public.warehouses (
    warehouse_id uuid primary key default gen_random_uuid(),
    warehouse_code varchar(30) not null unique,
    warehouse_name varchar(120) not null,
    address text,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.inventory_balances (
    product_id uuid not null references public.products(product_id) on delete restrict,
    warehouse_id uuid not null references public.warehouses(warehouse_id) on delete restrict,
    quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
    reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
    reorder_point integer not null default 0 check (reorder_point >= 0),
    updated_at timestamptz not null default now(),
    primary key (product_id, warehouse_id),
    check (reserved_quantity <= quantity_on_hand)
);

create table if not exists public.inventory_movements (
    movement_id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(product_id) on delete restrict,
    warehouse_id uuid not null references public.warehouses(warehouse_id) on delete restrict,
    movement_type varchar(20) not null
        check (movement_type in ('opening','receipt','dispatch','return','adjustment')),
    quantity_delta integer not null check (quantity_delta <> 0),
    reason text,
    reference_code varchar(100),
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_orders (
    purchase_order_id uuid primary key default gen_random_uuid(),
    purchase_order_number varchar(40) not null unique,
    supplier_id uuid not null references public.suppliers(supplier_id) on delete restrict,
    order_status varchar(20) not null default 'draft'
        check (order_status in ('draft','submitted','partially_received','received','cancelled')),
    ordered_at timestamptz,
    expected_at timestamptz,
    received_at timestamptz,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (expected_at is null or ordered_at is null or expected_at >= ordered_at)
);

create table if not exists public.purchase_order_items (
    purchase_order_item_id uuid primary key default gen_random_uuid(),
    purchase_order_id uuid not null references public.purchase_orders(purchase_order_id) on delete cascade,
    product_id uuid not null references public.products(product_id) on delete restrict,
    quantity_ordered integer not null check (quantity_ordered > 0),
    quantity_received integer not null default 0 check (quantity_received >= 0),
    unit_cost numeric(12,2) not null check (unit_cost >= 0),
    line_total numeric(14,2) generated always as (quantity_ordered * unit_cost) stored,
    created_at timestamptz not null default now(),
    unique (purchase_order_id, product_id),
    check (quantity_received <= quantity_ordered)
);

create index if not exists idx_inventory_balances_warehouse
    on public.inventory_balances(warehouse_id);
create index if not exists idx_inventory_movements_product_date
    on public.inventory_movements(product_id, created_at desc);
create index if not exists idx_inventory_movements_warehouse_date
    on public.inventory_movements(warehouse_id, created_at desc);
create index if not exists idx_purchase_orders_status_date
    on public.purchase_orders(order_status, created_at desc);
create index if not exists idx_purchase_order_items_product
    on public.purchase_order_items(product_id);

drop trigger if exists trg_warehouses_updated_at on public.warehouses;
create trigger trg_warehouses_updated_at before update on public.warehouses
for each row execute function public.set_updated_at();
drop trigger if exists trg_inventory_balances_updated_at on public.inventory_balances;
create trigger trg_inventory_balances_updated_at before update on public.inventory_balances
for each row execute function public.set_updated_at();
drop trigger if exists trg_purchase_orders_updated_at on public.purchase_orders;
create trigger trg_purchase_orders_updated_at before update on public.purchase_orders
for each row execute function public.set_updated_at();

-- Seed one warehouse and migrate existing aggregate stock into its opening balance.
insert into public.warehouses (warehouse_code, warehouse_name)
values ('MAIN', 'Main warehouse')
on conflict (warehouse_code) do nothing;

insert into public.inventory_balances (product_id, warehouse_id, quantity_on_hand, reorder_point)
select p.product_id, w.warehouse_id, p.stock_quantity, p.reorder_point
from public.products p
cross join public.warehouses w
where w.warehouse_code = 'MAIN'
on conflict (product_id, warehouse_id) do nothing;

insert into public.inventory_movements (
        product_id, warehouse_id, movement_type, quantity_delta, reason
)
select b.product_id, b.warehouse_id, 'opening', b.quantity_on_hand,
             'Opening balance migrated from products.stock_quantity'
from public.inventory_balances b
where b.quantity_on_hand > 0
    and not exists (
            select 1
            from public.inventory_movements m
            where m.product_id = b.product_id and m.warehouse_id = b.warehouse_id
    );

-- All stock changes go through this transaction so balances, product totals,
-- and the immutable movement ledger stay in sync.
create or replace function public.record_inventory_movement(
    p_product_id uuid,
    p_warehouse_id uuid,
    p_movement_type text,
    p_quantity_delta integer,
    p_reason text default null,
    p_reference_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_movement_id uuid;
begin
    if p_quantity_delta is null or p_quantity_delta = 0 then
        raise exception 'quantity_delta must be a non-zero integer';
    end if;

    if p_movement_type not in ('opening','receipt','dispatch','return','adjustment') then
        raise exception 'Unsupported inventory movement type: %', p_movement_type;
    end if;

    if p_movement_type in ('opening','receipt','return') and p_quantity_delta < 0 then
        raise exception 'Opening, receipt, and return movements must add stock';
    end if;

    if p_movement_type = 'dispatch' and p_quantity_delta > 0 then
        raise exception 'Dispatch movements must remove stock';
    end if;

    perform 1
    from public.products
    where product_id = p_product_id
    for update;

    if not found then
        raise exception 'Product not found: %', p_product_id;
    end if;

    insert into public.inventory_balances (product_id, warehouse_id)
    values (p_product_id, p_warehouse_id)
    on conflict (product_id, warehouse_id) do nothing;

    update public.inventory_balances
    set quantity_on_hand = quantity_on_hand + p_quantity_delta,
        updated_at = now()
    where product_id = p_product_id
      and warehouse_id = p_warehouse_id
      and quantity_on_hand + p_quantity_delta >= reserved_quantity;

    if not found then
        raise exception 'Movement would reduce available stock below reserved quantity';
    end if;

    insert into public.inventory_movements (
        product_id, warehouse_id, movement_type, quantity_delta, reason, reference_code
    ) values (
        p_product_id, p_warehouse_id, p_movement_type, p_quantity_delta, p_reason, p_reference_code
    ) returning movement_id into v_movement_id;

    update public.products
    set stock_quantity = (
        select coalesce(sum(quantity_on_hand), 0)::integer
        from public.inventory_balances
        where product_id = p_product_id
    )
    where product_id = p_product_id;

    return v_movement_id;
end;
$$;

revoke all on function public.record_inventory_movement(uuid, uuid, text, integer, text, text)
    from public, anon, authenticated;
grant execute on function public.record_inventory_movement(uuid, uuid, text, integer, text, text)
    to service_role;

create or replace view public.inventory_dashboard_summary
with (security_invoker = true)
as
select
    count(*) filter (where is_active) as active_products,
    coalesce(sum(stock_quantity) filter (where is_active), 0)::bigint as units_on_hand,
    count(*) filter (where is_active and stock_quantity <= reorder_point) as products_to_reorder,
    coalesce(sum(unit_cost * stock_quantity) filter (where is_active), 0)::numeric(14,2) as inventory_cost_value
from public.products;

create or replace view public.inventory_reorder_alerts
with (security_invoker = true)
as
select
    p.product_id,
    p.sku,
    p.product_name,
    p.category,
    p.stock_quantity,
    p.reorder_point,
    p.primary_supplier_id,
    s.supplier_name,
    (p.reorder_point - p.stock_quantity) as suggested_shortage
from public.products p
left join public.suppliers s on s.supplier_id = p.primary_supplier_id
where p.is_active and p.stock_quantity <= p.reorder_point;

create or replace view public.inventory_movement_daily
with (security_invoker = true)
as
select
    date_trunc('day', created_at)::date as movement_date,
    movement_type,
    sum(quantity_delta)::bigint as net_units,
    count(*)::bigint as movement_count
from public.inventory_movements
group by date_trunc('day', created_at)::date, movement_type;

-- New operational tables and AI analysis results are private by default.
-- Add explicit staff policies after defining your auth.users-to-staff mapping.
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.supplier_products enable row level security;
alter table public.shipments enable row level security;
alter table public.ai_agent_logs enable row level security;
alter table public.warehouses enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
