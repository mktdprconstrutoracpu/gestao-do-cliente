-- ============================================================================
-- Gestao do Cliente DPR - 002: cada pessoa le o proprio perfil
--
-- Para quem ja rodou o sql/001_obras.sql antes de 09/10/2026. (O 001 atual ja
-- traz esta trava; rodar os dois nao estraga nada.)
--
-- O PROBLEMA: a trava de leitura de obras_perfis so deixava ler quem ja esta
-- ATIVO na equipe. Quem acabou de pedir acesso (e ficou aguardando um gestor
-- liberar) nao enxergava o proprio cadastro: a leitura voltava vazia e a tela
-- voltava para "Sua conta ainda nao esta no painel", como se nada tivesse
-- acontecido ("quando eu coloco entrar na equipe nao acontece nada").
--
-- COMO RODAR
-- Supabase > SQL Editor > New query > colar este arquivo > Run.
-- ============================================================================
drop policy if exists obras_perfis_le_o_proprio on public.obras_perfis;
create policy obras_perfis_le_o_proprio on public.obras_perfis
  for select to authenticated
  using (user_id = auth.uid());
