-- ============================================================================
-- Gestao do Cliente DPR - 003: liberar acesso escrevendo "liberado"
--
-- Pedido de 13/10/2026: "tem como criar uma coluna no banco pra eu escrever
-- liberado e liberar?". Tem: a tabela obras_liberacoes, uma linha por login
-- (auth.users), com a coluna liberado. Pelo Table Editor do Supabase, escreva
-- liberado nessa coluna e a pessoa entra no painel de obras na hora, com o
-- papel da coluna papel. Apague a palavra (ou escreva nao) e ela perde o
-- acesso. O que o painel le continua sendo obras_perfis; esta tabela e o
-- controle remoto dela.
--
-- COMO RODAR
-- Supabase > SQL Editor > New query > colar este arquivo inteiro > Run.
-- Pode rodar mais de uma vez. Precisa do 001 ja rodado.
--
-- COMO USAR  (Supabase > Table Editor > obras_liberacoes)
--   email      o login da pessoa; todo login ja aparece aqui sozinho
--   nome       como ela aparece no painel (em branco = parte do e-mail antes do @)
--   papel      gestor, aprovador ou obra (padrao: obra)
--   liberado   escreva liberado para liberar; apague ou escreva nao para tirar
--   resultado  o banco escreve aqui o que fez (so leitura)
--
-- A tabela se mantem sozinha: quem cria login aparece nela; quem pede entrada
-- pelo painel aparece como "pediu entrada"; quem um gestor aprova na aba
-- Equipe aparece como liberado. Apagar uma linha tambem tira o acesso.
-- O navegador nao le nem escreve esta tabela (RLS ligado, sem politica).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. A tabela
-- ----------------------------------------------------------------------------
create table if not exists public.obras_liberacoes (
  email          text primary key,
  nome           text,
  papel          text not null default 'obra'
    check (papel in ('gestor', 'aprovador', 'obra')),
  liberado       text,
  resultado      text,
  atualizado_em  timestamptz not null default now()
);

comment on table  public.obras_liberacoes          is 'Controle de acesso do painel de obras: escreva liberado na coluna liberado.';
comment on column public.obras_liberacoes.liberado  is 'Escreva liberado para liberar; apague ou escreva nao para tirar o acesso.';
comment on column public.obras_liberacoes.papel     is 'gestor, aprovador ou obra.';
comment on column public.obras_liberacoes.resultado is 'So leitura: o banco escreve aqui o que fez.';

alter table public.obras_liberacoes enable row level security;
revoke all on table public.obras_liberacoes from public, anon, authenticated;


-- ----------------------------------------------------------------------------
-- 2. O que conta como "liberado" (tolera maiusculas e espacos)
-- ----------------------------------------------------------------------------
create or replace function public.obras_liberado_sim(p text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p, ''))) in ('liberado', 'liberada', 'liberar', 'sim', 'ok')
$$;


-- ----------------------------------------------------------------------------
-- 3. Escreveu na tabela: aplica em obras_perfis
--
-- Antes de cada insert/update. Roda como postgres (security definer), por
-- isso passa pela trava obras_protege_perfil. Quando a escrita veio de outro
-- gatilho (o espelho de obras_perfis, o de auth.users), so grava o que veio:
-- pg_trigger_depth() > 1.
-- ----------------------------------------------------------------------------
create or replace function public.obras_liberacoes_aplica()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid;
  v_perfil  public.obras_perfis;
  v_tem     boolean := false;
  v_sim     boolean;
  v_mudou   boolean;
  v_quando  text := to_char(now() - interval '3 hours', 'DD/MM/YYYY HH24:MI');  -- horario de Brasilia
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  new.email := lower(trim(coalesce(new.email, '')));
  if new.email = '' then
    raise exception 'Escreva o e-mail da pessoa.';
  end if;
  new.papel := lower(trim(coalesce(new.papel, '')));
  if new.papel = '' then
    new.papel := 'obra';
  end if;
  new.nome := nullif(trim(coalesce(new.nome, '')), '');
  new.atualizado_em := now();

  v_mudou := tg_op = 'INSERT'
          or new.liberado is distinct from old.liberado
          or new.papel    is distinct from old.papel
          or new.nome     is distinct from old.nome
          or new.email    is distinct from old.email;
  if not v_mudou then
    return new;
  end if;

  v_sim := public.obras_liberado_sim(new.liberado);

  select u.id into v_uid
    from auth.users u
   where lower(u.email) = new.email
   limit 1;

  if v_uid is not null then
    select p.* into v_perfil from public.obras_perfis p where p.user_id = v_uid;
    v_tem := found;
  end if;

  -- liberar
  if v_sim then
    new.liberado := 'liberado';
    if v_uid is null then
      new.resultado := 'Nao achei login com este e-mail. A pessoa cria a conta primeiro (Central, CRM ou painel de obras); depois escreva liberado de novo. ' || v_quando;
      return new;
    end if;

    insert into public.obras_perfis (user_id, nome, email, papel, ativo, aprovado_em)
         values (v_uid, coalesce(new.nome, split_part(new.email, '@', 1)), new.email, new.papel, true, now())
    on conflict (user_id) do update
         set papel       = excluded.papel,
             ativo       = true,
             aprovado_em = coalesce(public.obras_perfis.aprovado_em, now()),
             nome        = coalesce(new.nome, public.obras_perfis.nome);

    if new.nome is null then
      select p.nome into new.nome from public.obras_perfis p where p.user_id = v_uid;
    end if;
    new.resultado := 'Liberado como ' || new.papel || ' em ' || v_quando || '.';
    return new;
  end if;

  -- sem a palavra
  if nullif(trim(coalesce(new.liberado, '')), '') is not null then
    new.liberado := 'nao';
  end if;

  if v_uid is null then
    new.resultado := 'Nao achei login com este e-mail. A pessoa cria a conta primeiro (Central, CRM ou painel de obras). ' || v_quando;
  elsif v_tem and v_perfil.ativo then
    update public.obras_perfis
       set ativo = false,
           aprovado_em = coalesce(aprovado_em, now())
     where user_id = v_uid;
    new.resultado := 'Acesso retirado em ' || v_quando || '. Escreva liberado para liberar de novo.';
  elsif v_tem and v_perfil.aprovado_em is null then
    new.resultado := 'Pediu entrada pelo painel como ' || v_perfil.papel || '. Escreva liberado para liberar.';
  else
    new.resultado := 'Sem acesso. Escreva liberado para liberar.';
  end if;
  return new;
end;
$$;


-- ----------------------------------------------------------------------------
-- 4. Apagou a linha: tira o acesso
-- ----------------------------------------------------------------------------
create or replace function public.obras_liberacoes_apagada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if pg_trigger_depth() > 1 then
    return old;
  end if;
  select u.id into v_uid from auth.users u where lower(u.email) = lower(trim(old.email)) limit 1;
  if v_uid is not null then
    update public.obras_perfis
       set ativo = false,
           aprovado_em = coalesce(aprovado_em, now())
     where user_id = v_uid
       and ativo;
  end if;
  return old;
end;
$$;

drop trigger if exists obras_liberacoes_apagada on public.obras_liberacoes;
create trigger obras_liberacoes_apagada
  before delete on public.obras_liberacoes
  for each row execute function public.obras_liberacoes_apagada();


-- ----------------------------------------------------------------------------
-- 5. Espelho: mudou em obras_perfis (aba Equipe, obras_registrar,
--    obras_promover_gestor), a tabela mostra
-- ----------------------------------------------------------------------------
create or replace function public.obras_perfis_espelha()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quando text := to_char(now() - interval '3 hours', 'DD/MM/YYYY HH24:MI');
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;
  insert into public.obras_liberacoes (email, nome, papel, liberado, resultado, atualizado_em)
  values (
    lower(trim(new.email)),
    new.nome,
    new.papel,
    case when new.ativo then 'liberado' when new.aprovado_em is null then null else 'nao' end,
    case when new.ativo then 'Liberado como ' || new.papel || ' em ' || v_quando || '.'
         when new.aprovado_em is null then 'Pediu entrada pelo painel como ' || new.papel || '. Escreva liberado para liberar.'
         else 'Acesso retirado em ' || v_quando || '. Escreva liberado para liberar de novo.' end,
    now()
  )
  on conflict (email) do update
    set nome          = excluded.nome,
        papel         = excluded.papel,
        liberado      = excluded.liberado,
        resultado     = excluded.resultado,
        atualizado_em = now();
  return null;
end;
$$;

drop trigger if exists obras_perfis_espelha on public.obras_perfis;
create trigger obras_perfis_espelha
  after insert or update on public.obras_perfis
  for each row execute function public.obras_perfis_espelha();

create or replace function public.obras_perfis_some()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;
  delete from public.obras_liberacoes where email = lower(trim(old.email));
  return null;
end;
$$;

drop trigger if exists obras_perfis_some on public.obras_perfis;
create trigger obras_perfis_some
  after delete on public.obras_perfis
  for each row execute function public.obras_perfis_some();


-- ----------------------------------------------------------------------------
-- 6. Todo login novo aparece na tabela (e some quando o login e apagado)
--
-- Gatilhos em auth.users, como a documentacao do Supabase mostra. Nunca podem
-- atrapalhar a criacao da conta: qualquer erro e engolido.
-- ----------------------------------------------------------------------------
create or replace function public.obras_liberacoes_novo_login()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is null then
    return new;
  end if;
  insert into public.obras_liberacoes (email, nome, papel, liberado, resultado)
  values (
    lower(trim(new.email)),
    coalesce(new.raw_user_meta_data ->> 'nome', new.raw_user_meta_data ->> 'name'),
    'obra',
    null,
    'Sem acesso. Escreva liberado para liberar.'
  )
  on conflict (email) do nothing;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists obras_liberacoes_novo_login on auth.users;
create trigger obras_liberacoes_novo_login
  after insert on auth.users
  for each row execute function public.obras_liberacoes_novo_login();

create or replace function public.obras_liberacoes_login_apagado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.email is not null then
    delete from public.obras_liberacoes where email = lower(trim(old.email));
  end if;
  return old;
exception when others then
  return old;
end;
$$;

drop trigger if exists obras_liberacoes_login_apagado on auth.users;
create trigger obras_liberacoes_login_apagado
  after delete on auth.users
  for each row execute function public.obras_liberacoes_login_apagado();


-- ----------------------------------------------------------------------------
-- 7. Preenche a tabela com quem ja existe (sem o gatilho de aplicar, para
--    nao mexer em nenhum acesso) e so entao liga o gatilho
-- ----------------------------------------------------------------------------
drop trigger if exists obras_liberacoes_aplica on public.obras_liberacoes;

insert into public.obras_liberacoes (email, nome, papel, liberado, resultado)
select lower(trim(p.email)),
       p.nome,
       p.papel,
       case when p.ativo then 'liberado' when p.aprovado_em is null then null else 'nao' end,
       case when p.ativo then 'Liberado como ' || p.papel || '.'
            when p.aprovado_em is null then 'Pediu entrada pelo painel como ' || p.papel || '. Escreva liberado para liberar.'
            else 'Sem acesso (desativado). Escreva liberado para liberar.' end
  from public.obras_perfis p
on conflict (email) do update
  set nome          = excluded.nome,
      papel         = excluded.papel,
      liberado      = excluded.liberado,
      resultado     = excluded.resultado,
      atualizado_em = now();

insert into public.obras_liberacoes (email, nome, papel, liberado, resultado)
select lower(trim(u.email)),
       coalesce(u.raw_user_meta_data ->> 'nome', u.raw_user_meta_data ->> 'name'),
       'obra',
       null,
       'Sem acesso. Escreva liberado para liberar.'
  from auth.users u
 where u.email is not null
on conflict (email) do nothing;

create trigger obras_liberacoes_aplica
  before insert or update on public.obras_liberacoes
  for each row execute function public.obras_liberacoes_aplica();
