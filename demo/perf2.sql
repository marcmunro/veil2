
create table x as select * from veil2.privileges;
create table y as select * from veil2.privileges;
create table z as select * from veil2.privileges;
alter table x enable row level security;
alter table y enable row level security;
create policy x__select on x for select using (veil2.always_true(4));
create policy y__select on y for select using (veil2.i_have_global_priv(4));
grant select on x to demouser;
grant select on y to demouser;
grant select on z to demouser;
grant execute on function veil2.result_counts() to demouser;
