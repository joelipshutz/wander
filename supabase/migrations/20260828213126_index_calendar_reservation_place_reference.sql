-- Cover the nullable place foreign key so place deletion and reservation joins
-- do not require a full reservation-table scan.

create index if not exists calendar_reservations_resolved_place_id_idx
  on public.calendar_reservations(resolved_place_id);
