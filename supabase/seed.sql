-- Development seed data only. This file must never be applied to production.

insert into public.deal_categories (name, slug)
values ('Allgemein', 'allgemein')
on conflict (slug) do nothing;
