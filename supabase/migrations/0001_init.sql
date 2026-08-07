-- FinFlow cloud sync schema (v1)
-- Mirrors the local Drift tables (snake_case columns) plus per-row ownership
-- and soft-delete columns that power the delta sync engine.
--
-- Run this in the Supabase SQL editor (or `supabase db push`). Then enable
-- Email sign-in in Authentication > Providers (and Phone with an SMS
-- provider if you want phone OTP).
--
-- The app only ever talks to these tables with the signed-in user's JWT;
-- Row Level Security scopes every read/write to that user's own rows, so the
-- anon publishable key is safe to embed in the app.

-- ---------------------------------------------------------------------------
-- accounts (real accounts, categories and the system account)
-- ---------------------------------------------------------------------------
create table if not exists public.accounts (
  id text primary key,
  user_id uuid not null default auth.uid(),
  name text not null,
  institution text,
  kind text not null,
  type text not null,
  status text not null,
  opening_balance_minor bigint not null default 0,
  currency_code text not null,
  color_value bigint not null,
  icon_code text,
  notes text,
  sort_order bigint not null default 0,
  is_hidden boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists accounts_user_updated_idx
  on public.accounts (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id text primary key,
  user_id uuid not null default auth.uid(),
  type text not null,
  amount_minor bigint not null,
  currency_code text not null,
  occurred_at timestamptz not null,
  note text,
  merchant text,
  reference_number text,
  location text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists transactions_user_updated_idx
  on public.transactions (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- ledger_entries (children of transactions; replaced wholesale on edit)
-- ---------------------------------------------------------------------------
create table if not exists public.ledger_entries (
  id text primary key,
  user_id uuid not null default auth.uid(),
  transaction_id text not null,
  account_id text not null,
  direction text not null,
  amount_minor bigint not null,
  currency_code text not null
);
create index if not exists ledger_entries_transaction_idx
  on public.ledger_entries (transaction_id);
create index if not exists ledger_entries_user_idx
  on public.ledger_entries (user_id);

-- ---------------------------------------------------------------------------
-- tags
-- ---------------------------------------------------------------------------
create table if not exists public.tags (
  id text primary key,
  user_id uuid not null default auth.uid(),
  name text not null,
  color_value bigint,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists tags_user_updated_idx
  on public.tags (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- transaction_tags (children of transactions)
-- ---------------------------------------------------------------------------
create table if not exists public.transaction_tags (
  transaction_id text not null,
  tag_id text not null,
  user_id uuid not null default auth.uid(),
  primary key (transaction_id, tag_id)
);
create index if not exists transaction_tags_user_idx
  on public.transaction_tags (user_id);

-- ---------------------------------------------------------------------------
-- bills
-- ---------------------------------------------------------------------------
create table if not exists public.bills (
  id text primary key,
  user_id uuid not null default auth.uid(),
  name text not null,
  amount_minor bigint not null,
  currency_code text not null,
  account_id text,
  due_day_of_month bigint not null default 1,
  reminder_days_before bigint not null default 3,
  is_active boolean not null default true,
  last_paid_on timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists bills_user_updated_idx
  on public.bills (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------------
create table if not exists public.budgets (
  id text primary key,
  user_id uuid not null default auth.uid(),
  category_id text not null,
  amount_minor bigint not null,
  currency_code text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists budgets_user_updated_idx
  on public.budgets (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- app_settings (key-value; device-local secrets excluded by the client)
-- ---------------------------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key,
  user_id uuid not null default auth.uid(),
  value text not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);
create index if not exists app_settings_user_updated_idx
  on public.app_settings (user_id, updated_at);

-- ---------------------------------------------------------------------------
-- Row Level Security: every user can only touch their own rows.
-- ---------------------------------------------------------------------------
alter table public.accounts enable row level security;
alter table public.transactions enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.tags enable row level security;
alter table public.transaction_tags enable row level security;
alter table public.bills enable row level security;
alter table public.budgets enable row level security;
alter table public.app_settings enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'transactions', 'ledger_entries', 'tags', 'transaction_tags',
    'bills', 'budgets', 'app_settings'
  ] loop
    execute format(
      'create policy "own_rows_%1$s" on public.%1$s '
      'for all using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Grants (public schema defaults usually cover this; explicit is safer).
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on all tables in schema public
  to anon, authenticated;
