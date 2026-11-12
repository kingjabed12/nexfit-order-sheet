-- NEXFIT Order Management: customer detail parsing, image-only product gallery and packaging notes.
begin;

alter table public.customers
 add column if not exists customer_details text not null default '',
 add column if not exists customer_contact_phone text not null default '',
 add column if not exists customer_address text not null default '',
 add column if not exists product_images jsonb not null default '[]'::jsonb;

create table if not exists public.nexfit_products (
 id uuid primary key default gen_random_uuid(),
 image_path text not null,
 active boolean not null default true,
 created_by uuid null,
 created_at timestamptz not null default now()
);
create index if not exists nexfit_products_active_created_idx
 on public.nexfit_products(active,created_at desc);
alter table public.nexfit_products enable row level security;

drop policy if exists "nexfit products active read" on public.nexfit_products;
drop policy if exists "nexfit products admin insert" on public.nexfit_products;
drop policy if exists "nexfit products admin update" on public.nexfit_products;
drop policy if exists "nexfit products admin delete" on public.nexfit_products;

create policy "nexfit products active read" on public.nexfit_products
 for select to authenticated using (public.nexfit_is_active_user());
create policy "nexfit products admin insert" on public.nexfit_products
 for insert to authenticated with check (public.nexfit_is_admin());
create policy "nexfit products admin update" on public.nexfit_products
 for update to authenticated using (public.nexfit_is_admin()) with check (public.nexfit_is_admin());
create policy "nexfit products admin delete" on public.nexfit_products
 for delete to authenticated using (public.nexfit_is_admin());

revoke all on public.nexfit_products from anon;
grant select,insert,update,delete on public.nexfit_products to authenticated;

-- Public read is intentional for product thumbnails; only Admin can upload or modify files.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('nexfit-products','nexfit-products',true,8388608,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=8388608,
 allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "nexfit product images admin upload" on storage.objects;
drop policy if exists "nexfit product images admin update" on storage.objects;
drop policy if exists "nexfit product images admin delete" on storage.objects;

create policy "nexfit product images admin upload" on storage.objects
 for insert to authenticated with check (
  bucket_id='nexfit-products' and public.nexfit_is_admin()
);
create policy "nexfit product images admin update" on storage.objects
 for update to authenticated using (
  bucket_id='nexfit-products' and public.nexfit_is_admin()
) with check (
  bucket_id='nexfit-products' and public.nexfit_is_admin()
);
create policy "nexfit product images admin delete" on storage.objects
 for delete to authenticated using (
  bucket_id='nexfit-products' and public.nexfit_is_admin()
);

commit;
