-- ============================================================================
-- Gestao do Cliente DPR - 004: o cliente da Central ve a obra mesmo que o
-- nome do empreendimento nao bata com o da casa dele
--
-- Pedido de 13/10/2026: "a Central vai aparecer de um empreendimento so,
-- entao tudo que entrar na gestao de obra pode ir pra Central". No painel o
-- empreendimento foi cadastrado como "Villagio Caucaia 2" e na Central a casa
-- esta como "VILLAGIO CAUCAIA II": com a regra do 001 (nome igual), o cliente
-- nao via nada.
--
-- O QUE MUDA
--   Antes: o cliente (login da Central com vinculo aprovado) so lia o
--          empreendimento cujo nome batia com o da casa dele.
--   Agora: todo cliente com vinculo aprovado le os empreendimentos em
--          acompanhamento (ativo), as etapas deles e as atualizacoes
--          APROVADAS deles. O que continua igual: so o aprovado chega ao
--          cliente; quem envia nao decide; a equipe da obra nao ve dado
--          financeiro.
--   A Central escolhe qual mostrar: o de nome igual ao da casa; se nao houver
--   e so existir um empreendimento, mostra esse. Com dois ou mais e nenhum
--   nome igual, volta a mostrar a demonstracao (para nao mostrar a obra
--   errada). Quando houver mais de um empreendimento, basta deixar os nomes
--   iguais aos da Central, como o 001 sempre pediu.
--
-- COMO RODAR
-- Supabase > SQL Editor > New query > colar este arquivo inteiro > Run.
-- Pode rodar mais de uma vez. Precisa do 001 ja rodado.
-- ============================================================================

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
      join public.obras_empreendimentos e on e.id = p_emp
     where v.user_id = auth.uid()
       and v.situacao = 'aprovado'
       and e.ativo
  )
$$;

revoke all on function public.obras_cliente_do_empreendimento(bigint) from public, anon;
grant execute on function public.obras_cliente_do_empreendimento(bigint) to authenticated;
