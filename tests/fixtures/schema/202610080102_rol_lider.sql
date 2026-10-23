-- El nuevo valor del enum debe confirmarse antes de usarlo en operaciones.
begin;
alter type public.rol_empresa add value if not exists 'lider';
commit;
