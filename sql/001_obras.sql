-- ============================================================================
-- Gestao do Cliente DPR - 001: a base da gestao de obras
--
-- Quem usa o painel (perfis e papeis), os empreendimentos com as suas etapas,
-- as atualizacoes de obra com a fila de aprovacao, o historico e as fotos.
-- Roda no MESMO projeto Supabase do Central DPR (portal do cliente) e do CRM.
-- Por isso tudo aqui comeca com obras_: nada colide com unidades, parcelas e
-- vinculos do portal, nem com as tabelas crm_ do CRM.
--
-- COMO RODAR
-- Supabase > SQL Editor > New query > colar este arquivo inteiro > Run.
-- Pode rodar mais de uma vez sem estragar nada ("if not exists", "create or
-- replace", "drop policy if exists").
--
-- DEPOIS DE RODAR
-- 1. Abra o painel e use "Criar conta". O PRIMEIRO cadastro vira gestor.
-- 2. Os seguintes (obra, aprovador) ficam aguardando o gestor aprovar na
--    aba Equipe.
-- Socorro, se precisar promover alguem a gestor por fora:
--      select public.obras_promover_gestor('email@da.pessoa');
--
-- QUEM VE O QUE (as travas valem no banco, nao so na tela)
--   gestor      tudo: pessoas, empreendimentos, etapas; envia e aprova
--   aprovador   ve todas as atualizacoes; aprova, pede ajuste ou recusa;
--               tambem pode enviar
--   obra        envia atualizacoes e ve SO as que ela mesma enviou
--   cliente do portal (sem perfil aqui): ve so as atualizacoes APROVADAS do
--               empreendimento da casa dele, pela Central (vinculo aprovado)
--   sem login   nada
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. obras_perfis - quem usa o painel e com que papel
--
-- Uma linha por login do Supabase (auth.users). O e-mail e copiado para ca
-- porque o navegador nao le auth.users.
--   ativo=false e aprovado_em nulo  -> aguardando aprovacao do gestor
--   ativo=false e aprovado_em cheio -> desativado (ou recusado) por um gestor
-- ----------------------------------------------------------------------------
create table if not exists public.obras_perfis (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  nome           text not null,
  email          text not null,
  telefone       text,
  papel          text not null default 'obra'
    check (papel in ('gestor', 'aprovador', 'obra')),
  ativo          boolean not null default true,
  aprovado_em    timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create unique index if not exists obras_perfis_email_idx
  on public.obras_perfis (lower(email));


-- ----------------------------------------------------------------------------
-- 2. Quem esta chamando: funcoes que as travas usam
--
-- security definer para ler obras_perfis por dentro, sem cair na propria
-- trava da tabela. stable: avaliada uma vez por consulta.
-- ----------------------------------------------------------------------------
create or replace function public.obras_papel()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.papel
    from public.obras_perfis p
   where p.user_id = auth.uid()
     and p.ativo
$$;

create or replace function public.obras_tem_acesso()
returns boolean language sql stable security definer set search_path = public
as $$ select public.obras_papel() is not null $$;

create or replace function public.obras_e_gestor()
returns boolean language sql stable security definer set search_path = public
as $$ select public.obras_papel() = 'gestor' $$;

-- quem decide: gestor ou aprovador
create or replace function public.obras_aprova()
returns boolean language sql stable security definer set search_path = public
as $$ select public.obras_papel() in ('gestor', 'aprovador') $$;

revoke all on function public.obras_papel()      from public, anon;
revoke all on function public.obras_tem_acesso() from public, anon;
revoke all on function public.obras_e_gestor()   from public, anon;
revoke all on function public.obras_aprova()     from public, anon;
grant execute on function public.obras_papel()      to authenticated;
grant execute on function public.obras_tem_acesso() to authenticated;
grant execute on function public.obras_e_gestor()   to authenticated;
grant execute on function public.obras_aprova()     to authenticated;


-- ----------------------------------------------------------------------------
-- 3. atualizado_em sempre em dia
-- ----------------------------------------------------------------------------
create or replace function public.obras_toca_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists obras_perfis_atualizado on public.obras_perfis;
create trigger obras_perfis_atualizado
  before update on public.obras_perfis
  for each row execute function public.obras_toca_atualizado_em();


-- ----------------------------------------------------------------------------
-- 4. Ninguem se promove: so gestor muda papel, situacao, aprovacao ou e-mail
--
-- A politica de UPDATE deixa cada pessoa editar o PROPRIO perfil (nome,
-- telefone). Sem este gatilho, alguem da obra trocaria o proprio papel para
-- gestor. A chave de servico (current_user service_role) passa direto.
-- ----------------------------------------------------------------------------
create or replace function public.obras_protege_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;
  if (new.papel       is distinct from old.papel
   or new.ativo       is distinct from old.ativo
   or new.aprovado_em is distinct from old.aprovado_em
   or new.email       is distinct from old.email
   or new.user_id     is distinct from old.user_id)
     and not public.obras_e_gestor() then
    raise exception 'Somente um gestor pode mudar papel, situacao, aprovacao ou e-mail de um perfil.';
  end if;
  return new;
end;
$$;

drop trigger if exists obras_perfis_protegido on public.obras_perfis;
create trigger obras_perfis_protegido
  before update on public.obras_perfis
  for each row execute function public.obras_protege_perfil();


-- ----------------------------------------------------------------------------
-- 5. obras_registrar(nome, papel) - a tela "Criar conta" chama logo depois do
--    signUp do Supabase, ja autenticada. Cria o perfil de quem chamou.
--
--   - o PRIMEIRO cadastro (quando ainda nao ha gestor ativo) vira gestor na
--     hora: e quem esta montando o painel;
--   - os seguintes entram com o papel pedido, INATIVOS e sem aprovacao. Um
--     gestor aprova na aba Equipe, podendo trocar o papel antes.
--
-- security definer: a tabela nao tem politica de INSERT para o navegador (de
-- proposito); so esta funcao escreve perfis novos. Idempotente.
-- ----------------------------------------------------------------------------
create or replace function public.obras_registrar(p_nome text, p_papel text)
returns public.obras_perfis
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_email      text;
  v_nome       text;
  v_papel      text;
  v_tem_gestor boolean;
  v_perfil     public.obras_perfis;
begin
  if v_uid is null then
    raise exception 'Precisa estar autenticado para se cadastrar.';
  end if;

  select p.* into v_perfil from public.obras_perfis p where p.user_id = v_uid;
  if found then
    return v_perfil;
  end if;

  select lower(u.email) into v_email from auth.users u where u.id = v_uid;
  if v_email is null then
    raise exception 'Login sem e-mail.';
  end if;

  v_nome  := coalesce(nullif(trim(p_nome), ''), split_part(v_email, '@', 1));
  v_papel := case when p_papel in ('gestor', 'aprovador', 'obra') then p_papel else 'obra' end;

  select exists (select 1 from public.obras_perfis where papel = 'gestor' and ativo) into v_tem_gestor;

  if not v_tem_gestor then
    insert into public.obras_perfis (user_id, nome, email, papel, ativo, aprovado_em)
         values (v_uid, v_nome, v_email, 'gestor', true, now())
      returning * into v_perfil;
  else
    insert into public.obras_perfis (user_id, nome, email, papel, ativo, aprovado_em)
         values (v_uid, v_nome, v_email, v_papel, false, null)
      returning * into v_perfil;
  end if;

  return v_perfil;
end;
$$;

revoke all on function public.obras_registrar(text, text) from public, anon;
grant execute on function public.obras_registrar(text, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 6. obras_promover_gestor(email) - socorro, roda so no SQL Editor
-- ----------------------------------------------------------------------------
create or replace function public.obras_promover_gestor(p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid;
  v_nome text;
begin
  select u.id,
         coalesce(u.raw_user_meta_data ->> 'nome', u.raw_user_meta_data ->> 'name', split_part(u.email, '@', 1))
    into v_uid, v_nome
    from auth.users u
   where lower(u.email) = lower(trim(p_email))
   limit 1;

  if v_uid is null then
    return 'Nao achei nenhum login com o e-mail ' || p_email || '. Crie a conta pela tela Criar conta do painel primeiro.';
  end if;

  insert into public.obras_perfis (user_id, nome, email, papel, ativo, aprovado_em)
       values (v_uid, v_nome, lower(trim(p_email)), 'gestor', true, now())
  on conflict (user_id) do update
        set papel = 'gestor', ativo = true, aprovado_em = coalesce(public.obras_perfis.aprovado_em, now());

  return 'Pronto: ' || p_email || ' e gestor do painel de obras.';
end;
$$;

revoke all on function public.obras_promover_gestor(text) from public, anon, authenticated;


-- ----------------------------------------------------------------------------
-- 7. obras_empreendimentos - cada obra acompanhada
--
-- O NOME e o elo com a Central do Cliente: la, cada casa tem o empreendimento
-- como texto ("VILLAGIO CAUCAIA II"). O cliente ve as atualizacoes do
-- empreendimento cujo nome bate com o da casa dele, sem diferenca de
-- maiusculas. Por isso o nome e unico ignorando maiusculas.
-- ----------------------------------------------------------------------------
create table if not exists public.obras_empreendimentos (
  id               bigint generated always as identity primary key,
  nome             text not null,
  cidade           text,
  inicio_obra      date,
  previsao_entrega date,
  ativo            boolean not null default true,     -- em acompanhamento
  observacoes      text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);

create unique index if not exists obras_empreendimentos_nome_idx
  on public.obras_empreendimentos (upper(trim(nome)));

drop trigger if exists obras_empreendimentos_atualizado on public.obras_empreendimentos;
create trigger obras_empreendimentos_atualizado
  before update on public.obras_empreendimentos
  for each row execute function public.obras_toca_atualizado_em();


-- ----------------------------------------------------------------------------
-- 8. obras_etapas - as etapas de cada empreendimento, em ordem
--
-- Sao as marcas da barra e os blocos da linha do tempo na Central. Todo
-- empreendimento novo nasce com quatro etapas padrao (as mesmas que a Central
-- ja desenha); o gestor renomeia ou acrescenta depois.
-- ----------------------------------------------------------------------------
create table if not exists public.obras_etapas (
  id                bigint generated always as identity primary key,
  empreendimento_id bigint not null
                      references public.obras_empreendimentos(id) on delete cascade,
  nome              text not null,
  ordem             int  not null,
  situacao          text not null default 'a_fazer'
    check (situacao in ('a_fazer', 'em_andamento', 'concluida')),
  previsao          date,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint obras_etapas_empreendimento_nome_key unique (empreendimento_id, nome)
);

create index if not exists obras_etapas_empreendimento_idx
  on public.obras_etapas (empreendimento_id, ordem);

drop trigger if exists obras_etapas_atualizado on public.obras_etapas;
create trigger obras_etapas_atualizado
  before update on public.obras_etapas
  for each row execute function public.obras_toca_atualizado_em();

create or replace function public.obras_etapas_padrao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.obras_etapas (empreendimento_id, nome, ordem) values
    (new.id, 'Fundação e terraplenagem',  10),
    (new.id, 'Estrutura e alvenaria',     20),
    (new.id, 'Instalações e acabamento',  30),
    (new.id, 'Paisagismo e entrega',      40)
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists obras_empreendimentos_etapas_padrao on public.obras_empreendimentos;
create trigger obras_empreendimentos_etapas_padrao
  after insert on public.obras_empreendimentos
  for each row execute function public.obras_etapas_padrao();


-- ----------------------------------------------------------------------------
-- 9. obras_atualizacoes - o que a obra envia e o que o aprovador decide
--
-- Nasce 'aguardando'. O aprovador (ou gestor) muda para 'aprovada', 'ajuste'
-- ou 'recusada'. Quem enviou pode corrigir enquanto esta 'aguardando' ou em
-- 'ajuste', e ao corrigir volta para 'aguardando'. So o que esta 'aprovada'
-- chega ao cliente. O gatilho abaixo garante isso no banco.
-- ----------------------------------------------------------------------------
create table if not exists public.obras_atualizacoes (
  id                   bigint generated always as identity primary key,
  empreendimento_id    bigint not null
                         references public.obras_empreendimentos(id) on delete restrict,
  etapa_id             bigint references public.obras_etapas(id) on delete set null,
  titulo               text not null,
  texto                text,
  percentual           int check (percentual between 0 and 100),
  data_referencia      date not null default current_date,
  situacao             text not null default 'aguardando'
    check (situacao in ('aguardando', 'aprovada', 'ajuste', 'recusada')),
  enviado_por          uuid not null default auth.uid() references auth.users(id),
  decidido_por         uuid references auth.users(id),
  decidido_em          timestamptz,
  observacao_aprovador text,
  publicado_em         timestamptz,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);

create index if not exists obras_atualizacoes_fila_idx
  on public.obras_atualizacoes (situacao, criado_em);
create index if not exists obras_atualizacoes_empreendimento_idx
  on public.obras_atualizacoes (empreendimento_id, situacao, data_referencia);

drop trigger if exists obras_atualizacoes_atualizado on public.obras_atualizacoes;
create trigger obras_atualizacoes_atualizado
  before update on public.obras_atualizacoes
  for each row execute function public.obras_toca_atualizado_em();

-- quem envia nao decide: na entrada, tudo nasce aguardando e em nome de quem
-- esta logado; na edicao, so quem aprova muda a situacao (e o banco carimba
-- quem decidiu e quando). Quem enviou, ao corrigir, volta para aguardando.
create or replace function public.obras_protege_atualizacao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.enviado_por          := coalesce(auth.uid(), new.enviado_por);
    new.situacao             := 'aguardando';
    new.decidido_por         := null;
    new.decidido_em          := null;
    new.observacao_aprovador := null;
    new.publicado_em         := null;
    return new;
  end if;

  -- UPDATE
  if new.enviado_por is distinct from old.enviado_por
     or new.empreendimento_id is distinct from old.empreendimento_id then
    raise exception 'Nao da para trocar quem enviou nem o empreendimento de uma atualizacao.';
  end if;

  if public.obras_aprova() then
    if new.situacao is distinct from old.situacao then
      new.decidido_por := auth.uid();
      new.decidido_em  := now();
      new.publicado_em := case when new.situacao = 'aprovada' then now() else null end;
    end if;
    return new;
  end if;

  -- quem enviou: so mexe no proprio, enquanto nao foi decidido de vez
  if old.enviado_por <> auth.uid() then
    raise exception 'Voce so pode alterar as atualizacoes que voce enviou.';
  end if;
  if old.situacao not in ('aguardando', 'ajuste') then
    raise exception 'Esta atualizacao ja foi decidida; envie uma nova.';
  end if;
  if new.decidido_por is distinct from old.decidido_por
     or new.decidido_em is distinct from old.decidido_em
     or new.observacao_aprovador is distinct from old.observacao_aprovador
     or new.publicado_em is distinct from old.publicado_em then
    raise exception 'Somente um aprovador decide sobre a atualizacao.';
  end if;
  -- corrigiu depois de um pedido de ajuste: volta para a fila
  new.situacao := 'aguardando';
  return new;
end;
$$;

drop trigger if exists obras_atualizacoes_protegida on public.obras_atualizacoes;
create trigger obras_atualizacoes_protegida
  before insert or update on public.obras_atualizacoes
  for each row execute function public.obras_protege_atualizacao();


-- ----------------------------------------------------------------------------
-- 10. obras_eventos - a linha do tempo de cada atualizacao
--
-- Quem fez o que e quando: enviada, reenviada, aprovada, ajuste pedido,
-- recusada, nota. Os eventos de situacao entram sozinhos pelo gatilho; a nota
-- e escrita pela tela.
-- ----------------------------------------------------------------------------
create table if not exists public.obras_eventos (
  id             bigint generated always as identity primary key,
  atualizacao_id bigint not null
                   references public.obras_atualizacoes(id) on delete cascade,
  tipo           text not null
    check (tipo in ('enviada', 'reenviada', 'aprovada', 'ajuste', 'recusada', 'nota')),
  texto          text,
  autor          uuid references auth.users(id),
  criado_em      timestamptz not null default now()
);

create index if not exists obras_eventos_atualizacao_idx
  on public.obras_eventos (atualizacao_id, criado_em);

create or replace function public.obras_registra_evento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.obras_eventos (atualizacao_id, tipo, texto, autor)
         values (new.id, 'enviada', new.titulo, new.enviado_por);
    return new;
  end if;
  if new.situacao is distinct from old.situacao then
    insert into public.obras_eventos (atualizacao_id, tipo, texto, autor)
         values (new.id,
                 case new.situacao when 'aguardando' then 'reenviada' else new.situacao end,
                 new.observacao_aprovador,
                 coalesce(auth.uid(), new.decidido_por, new.enviado_por));
  end if;
  return new;
end;
$$;

drop trigger if exists obras_atualizacoes_eventos on public.obras_atualizacoes;
create trigger obras_atualizacoes_eventos
  after insert or update on public.obras_atualizacoes
  for each row execute function public.obras_registra_evento();


-- ----------------------------------------------------------------------------
-- 11. obras_fotos - as fotos de cada atualizacao
--
-- O arquivo fica no Storage do Supabase (bucket "obras", abaixo); aqui fica o
-- caminho, a legenda e a ordem. O caminho e <user_id>/<atualizacao_id>/<arquivo>,
-- e e por essa primeira pasta que o Storage sabe de quem e a foto.
-- ----------------------------------------------------------------------------
create table if not exists public.obras_fotos (
  id             bigint generated always as identity primary key,
  atualizacao_id bigint not null
                   references public.obras_atualizacoes(id) on delete cascade,
  caminho        text not null,
  legenda        text,
  ordem          int not null default 0,
  enviado_por    uuid not null default auth.uid() references auth.users(id),
  criado_em      timestamptz not null default now()
);

create index if not exists obras_fotos_atualizacao_idx
  on public.obras_fotos (atualizacao_id, ordem);


-- ----------------------------------------------------------------------------
-- 12. O cliente do portal: ve so o que esta aprovado, do empreendimento dele
--
-- Liga esta base a Central: a casa do cliente (unidades) tem o empreendimento
-- como texto; o vinculo aprovado (vinculos) diz que a casa e dele. Se o nome
-- bater com um empreendimento daqui, ele le as atualizacoes aprovadas.
-- ----------------------------------------------------------------------------
create or replace function public.obras_cliente_do_empreendimento(p_emp bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.vinculos v
      join public.unidades u on u.id = v.unidade_id
      join public.obras_empreendimentos e on e.id = p_emp
     where v.user_id = auth.uid()
       and v.situacao = 'aprovado'
       and upper(trim(u.empreendimento)) = upper(trim(e.nome))
  )
$$;

-- quem pode ver uma atualizacao: quem aprova, quem enviou, ou o cliente do
-- empreendimento se ela estiver aprovada
create or replace function public.obras_ve_atualizacao(p_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.obras_atualizacoes a
     where a.id = p_id
       and (public.obras_aprova()
            or a.enviado_por = auth.uid()
            or (a.situacao = 'aprovada' and public.obras_cliente_do_empreendimento(a.empreendimento_id)))
  )
$$;

revoke all on function public.obras_cliente_do_empreendimento(bigint) from public, anon;
revoke all on function public.obras_ve_atualizacao(bigint)            from public, anon;
grant execute on function public.obras_cliente_do_empreendimento(bigint) to authenticated;
grant execute on function public.obras_ve_atualizacao(bigint)            to authenticated;


-- ============================================================================
-- 13. TRAVAS DE ACESSO (RLS)
-- ============================================================================
alter table public.obras_perfis          enable row level security;
alter table public.obras_empreendimentos enable row level security;
alter table public.obras_etapas          enable row level security;
alter table public.obras_atualizacoes    enable row level security;
alter table public.obras_eventos         enable row level security;
alter table public.obras_fotos           enable row level security;

-- perfis: quem tem acesso ve a equipe (precisa dos nomes de quem enviou e
-- de quem aprovou); cada um edita o proprio; gestor edita todos. Ninguem
-- insere ou apaga pelo navegador: entrar e pela obras_registrar, sair e
-- ficar inativo (historico).
drop policy if exists obras_perfis_le_equipe on public.obras_perfis;
create policy obras_perfis_le_equipe on public.obras_perfis
  for select to authenticated
  using (public.obras_tem_acesso());

-- cada pessoa le o PROPRIO perfil mesmo inativo ou aguardando liberacao
-- (09/10/2026): sem isto, quem acabou de pedir acesso nao enxergava o
-- proprio cadastro e a tela voltava para "ainda nao esta no painel". Quem ja
-- rodou o 001 antes desta linha roda o sql/002_perfil_proprio.sql.
drop policy if exists obras_perfis_le_o_proprio on public.obras_perfis;
create policy obras_perfis_le_o_proprio on public.obras_perfis
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists obras_perfis_edita_o_proprio on public.obras_perfis;
create policy obras_perfis_edita_o_proprio on public.obras_perfis
  for update to authenticated
  using (user_id = auth.uid() and public.obras_tem_acesso())
  with check (user_id = auth.uid());

drop policy if exists obras_perfis_gestor_edita on public.obras_perfis;
create policy obras_perfis_gestor_edita on public.obras_perfis
  for update to authenticated
  using (public.obras_e_gestor())
  with check (public.obras_e_gestor());

-- empreendimentos e etapas: a equipe le; so o gestor escreve; o cliente do
-- portal le o empreendimento da casa dele (para a barra e a linha do tempo)
drop policy if exists obras_empreendimentos_le on public.obras_empreendimentos;
create policy obras_empreendimentos_le on public.obras_empreendimentos
  for select to authenticated
  using (public.obras_tem_acesso() or public.obras_cliente_do_empreendimento(id));

drop policy if exists obras_empreendimentos_gestor on public.obras_empreendimentos;
create policy obras_empreendimentos_gestor on public.obras_empreendimentos
  for all to authenticated
  using (public.obras_e_gestor()) with check (public.obras_e_gestor());

drop policy if exists obras_etapas_le on public.obras_etapas;
create policy obras_etapas_le on public.obras_etapas
  for select to authenticated
  using (public.obras_tem_acesso() or public.obras_cliente_do_empreendimento(empreendimento_id));

drop policy if exists obras_etapas_gestor on public.obras_etapas;
create policy obras_etapas_gestor on public.obras_etapas
  for all to authenticated
  using (public.obras_e_gestor()) with check (public.obras_e_gestor());

-- aprovador e gestor marcam a situacao da etapa (concluida, em andamento)
drop policy if exists obras_etapas_aprovador_marca on public.obras_etapas;
create policy obras_etapas_aprovador_marca on public.obras_etapas
  for update to authenticated
  using (public.obras_aprova()) with check (public.obras_aprova());

-- atualizacoes: quem aprova ve tudo; quem enviou ve as suas; o cliente ve as
-- aprovadas do empreendimento dele. Insere quem tem acesso, em nome proprio.
-- Edita quem aprova, ou quem enviou enquanto aguarda ou esta em ajuste (o
-- gatilho acima decide o que cada um pode mudar). Apaga o gestor, ou quem
-- enviou enquanto ainda aguarda.
drop policy if exists obras_atualizacoes_le on public.obras_atualizacoes;
create policy obras_atualizacoes_le on public.obras_atualizacoes
  for select to authenticated
  using (public.obras_aprova()
         or enviado_por = auth.uid()
         or (situacao = 'aprovada' and public.obras_cliente_do_empreendimento(empreendimento_id)));

drop policy if exists obras_atualizacoes_envia on public.obras_atualizacoes;
create policy obras_atualizacoes_envia on public.obras_atualizacoes
  for insert to authenticated
  with check (public.obras_tem_acesso() and enviado_por = auth.uid());

drop policy if exists obras_atualizacoes_edita on public.obras_atualizacoes;
create policy obras_atualizacoes_edita on public.obras_atualizacoes
  for update to authenticated
  using (public.obras_aprova() or (enviado_por = auth.uid() and situacao in ('aguardando', 'ajuste')))
  with check (public.obras_aprova() or enviado_por = auth.uid());

drop policy if exists obras_atualizacoes_apaga on public.obras_atualizacoes;
create policy obras_atualizacoes_apaga on public.obras_atualizacoes
  for delete to authenticated
  using (public.obras_e_gestor() or (enviado_por = auth.uid() and situacao = 'aguardando'));

-- eventos: quem ve a atualizacao ve a linha do tempo; nota so de quem ve, em
-- nome proprio (os eventos de situacao entram pelo gatilho)
drop policy if exists obras_eventos_le on public.obras_eventos;
create policy obras_eventos_le on public.obras_eventos
  for select to authenticated
  using (public.obras_ve_atualizacao(atualizacao_id));

drop policy if exists obras_eventos_anota on public.obras_eventos;
create policy obras_eventos_anota on public.obras_eventos
  for insert to authenticated
  with check (tipo = 'nota' and autor = auth.uid() and public.obras_tem_acesso() and public.obras_ve_atualizacao(atualizacao_id));

-- fotos: quem ve a atualizacao ve as fotos; quem enviou a atualizacao poe e
-- tira fotos enquanto ela aguarda ou esta em ajuste; quem aprova tira
drop policy if exists obras_fotos_le on public.obras_fotos;
create policy obras_fotos_le on public.obras_fotos
  for select to authenticated
  using (public.obras_ve_atualizacao(atualizacao_id));

drop policy if exists obras_fotos_envia on public.obras_fotos;
create policy obras_fotos_envia on public.obras_fotos
  for insert to authenticated
  with check (enviado_por = auth.uid() and exists (
    select 1 from public.obras_atualizacoes a
     where a.id = atualizacao_id
       and (public.obras_aprova() or (a.enviado_por = auth.uid() and a.situacao in ('aguardando', 'ajuste')))));

drop policy if exists obras_fotos_apaga on public.obras_fotos;
create policy obras_fotos_apaga on public.obras_fotos
  for delete to authenticated
  using (public.obras_aprova() or (enviado_por = auth.uid() and exists (
    select 1 from public.obras_atualizacoes a
     where a.id = atualizacao_id and a.situacao in ('aguardando', 'ajuste'))));


-- ============================================================================
-- 14. STORAGE - o bucket "obras" para as fotos
--
-- Publico para LEITURA: a foto aprovada aparece na Central pelo endereco
-- direto, sem token. Quem SOBE e so quem tem acesso ao painel, e sempre numa
-- pasta com o proprio user_id (e assim que o Storage sabe de quem e). Quem
-- apaga e o dono da pasta ou quem aprova.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('obras', 'obras', true)
on conflict (id) do nothing;

drop policy if exists obras_storage_le on storage.objects;
create policy obras_storage_le on storage.objects
  for select
  using (bucket_id = 'obras');

drop policy if exists obras_storage_sobe on storage.objects;
create policy obras_storage_sobe on storage.objects
  for insert to authenticated
  with check (bucket_id = 'obras'
              and public.obras_tem_acesso()
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists obras_storage_apaga on storage.objects;
create policy obras_storage_apaga on storage.objects
  for delete to authenticated
  using (bucket_id = 'obras'
         and (public.obras_aprova() or (storage.foldername(name))[1] = auth.uid()::text));
