# Gestao do Cliente DPR

Painel interno da DPR Construtora para a **gestao de obras**: quem esta na
obra envia a atualizacao (etapa, percentual, texto e fotos), quem aprova
(Luana ou Rodrigo) libera, e so o que foi aprovado aparece para o cliente na
pagina "Evolucao da obra" da Central do Cliente. Mesmo padrao do Central e do
CRM: uma pagina (`index.html`), banco e login no Supabase, sem etapa de build,
publicado pela Vercel.

## As duas abas

| Aba | Quem usa | O que faz |
|---|---|---|
| **Enviar atualizacao** | papel `obra` (e tambem aprovador e gestor) | Entra com o proprio login e envia o que aconteceu na obra. Ve so o que ela mesma enviou e a situacao de cada envio |
| **Aprovar** | papel `aprovador` (Luana, Rodrigo) e `gestor` | A fila do que a obra enviou. Aprova, pede ajuste ou recusa. Nada chega ao cliente sem passar por aqui |

Mais duas abas, so do gestor: **Empreendimentos** (as obras acompanhadas, com
o mesmo nome que a Central usa) e **Equipe** (quem entra e com que papel).

## Etapas

1. **Base** (esta): banco, login, cadastro com aprovacao, as duas abas com a
   estrutura e o historico, Empreendimentos e Equipe.
2. **Enviar**: o formulario completo (empreendimento, etapa, percentual,
   texto, data, fotos no Storage), com edicao enquanto aguarda.
3. **Aprovar**: abrir cada atualizacao com as fotos, aprovar, pedir ajuste ou
   recusar com observacao, linha do tempo, marcar etapa concluida.
4. **Central lendo as aprovadas**: a pagina "Evolucao da obra" deixa de ser
   demonstracao e passa a mostrar as atualizacoes aprovadas do empreendimento
   da casa do cliente (as travas para isso ja estao no `sql/001_obras.sql`).
5. Aviso ao cliente quando sai atualizacao nova; aviso ao aprovador quando a
   obra envia.

## O que a etapa 1 tem

| Tela | O que faz |
|---|---|
| Entrar | E-mail e senha do Supabase; "Esqueci a senha" manda o link de recuperacao |
| Criar conta | Nome, e-mail, senha e papel (obra, aprovador, gestor). O **primeiro** cadastro vira gestor na hora; os seguintes ficam **aguardando liberacao** de um gestor |
| Sem acesso | Login que existe mas nao esta na equipe do painel (um cliente da Central, por exemplo) ve so esta tela |
| Enviar atualizacao | Resumo (obras em acompanhamento, enviadas por voce, aguardando, aprovadas) e a tabela do que voce enviou. O botao "Nova atualizacao" entra na etapa 2 |
| Aprovar | Resumo (aguardando, aprovadas, com ajuste, recusadas, obras) e a fila de aguardando, com quem enviou e quando. Aviso de cadastros aguardando liberacao (gestor) |
| Empreendimentos | Lista e cadastro: nome (igual ao da Central), cidade, inicio da obra, previsao de entrega, situacao, observacoes. Todo empreendimento novo nasce com quatro etapas padrao (Fundacao e terraplenagem, Estrutura e alvenaria, Instalacoes e acabamento, Paisagismo e entrega) |
| Equipe | Quem usa o painel e com que papel; o gestor libera ou recusa os cadastros novos (ajustando o papel antes, se quiser), troca o papel e desativa (nunca apaga) |

### Papeis

| Papel | Pode |
|---|---|
| gestor | tudo: libera cadastros, troca papel, desativa, cadastra empreendimentos e etapas, envia, aprova |
| aprovador | ve todas as atualizacoes; aprova, pede ajuste ou recusa; marca etapa concluida; tambem envia |
| obra | envia atualizacoes e ve **so as que ela mesma enviou**; corrige enquanto aguarda ou esta em ajuste |
| cliente da Central | sem perfil aqui; pela Central, le **so as atualizacoes aprovadas** do empreendimento da casa dele |

As travas valem **no banco** (RLS em `sql/001_obras.sql`), nao so na tela. Um
gatilho garante que quem envia nao decide: toda atualizacao nasce "aguardando",
so quem aprova muda a situacao, e o banco carimba quem decidiu e quando.

### Cadastro e liberacao

Qualquer pessoa com o endereco do painel pode criar conta, mas **ninguem entra
sem um gestor liberar**:

1. A pessoa cria a conta (nome, e-mail, senha, papel). O login nasce no
   Supabase Auth, com nome e papel guardados nos dados do login.
2. Na primeira sessao, o painel chama `obras_registrar` e o perfil nasce em
   `obras_perfis`: o primeiro de todos como gestor ativo; os demais com o
   papel pedido, inativos e sem `aprovado_em`. A pessoa ve "Cadastro recebido".
3. O gestor ve o aviso na aba Aprovar e na Equipe, confere o papel, ajusta se
   precisar e toca em Aprovar (ou Recusar). Liberado, a pessoa entra.

### O elo com a Central do Cliente

O painel, a Central e o CRM usam o **mesmo Supabase** (projeto
`roashkfdjgsweuftqhyx`) e o **mesmo login**. Os usuarios sao separados pela
tabela: so quem tem linha em `obras_perfis` entra no painel.

Na Central, cada casa tem o empreendimento como texto ("VILLAGIO CAUCAIA II").
O cliente com vinculo aprovado a uma casa le, direto do banco, as atualizacoes
**aprovadas** do empreendimento daqui cujo nome bate com o da casa (sem
diferenca de maiusculas). Por isso o nome aqui tem que ser igual ao da Central.

## Como colocar no ar

### 1. Banco (Supabase, o mesmo projeto do Central DPR e do CRM)

Supabase > SQL Editor > New query > colar `sql/001_obras.sql` inteiro > Run.
Pode rodar mais de uma vez. Tudo comeca com `obras_`; nada da Central nem do
CRM e tocado. O arquivo tambem cria o bucket `obras` no Storage, para as fotos.

O primeiro gestor e **quem criar a primeira conta** na tela "Criar conta". Se
precisar promover alguem a gestor por fora (socorro), no SQL Editor:
`select public.obras_promover_gestor('email@da.pessoa');`

### 2. Supabase > Authentication > URL Configuration

Em **Redirect URLs**, adicione o endereco do painel (o da Vercel e, depois, o
dominio). Sem isso o link de "esqueci a senha" nao volta para o painel.

### 3. Vercel

Importar o repositorio `gestao-do-cliente` como projeto novo (Framework
Preset: Other, sem Build Command). Nesta etapa **nao ha variavel de ambiente**:
a pagina fala com o Supabase direto, com a chave publicavel.

A chave publicavel (`sb_publishable_...`) esta no `index.html` de proposito:
ela e feita para o navegador e, sem login, nao abre nada.

## Como funciona por dentro

- `index.html`: HTML, CSS e script num arquivo so. Cada aba e uma rota por
  `#ancora` (enviar, aprovar, empreendimentos, equipe); o botao voltar do
  navegador funciona. A aba padrao e Aprovar para quem aprova e Enviar para
  quem esta na obra. O script le o perfil de quem entrou e esconde o que a
  pessoa nao pode fazer; a trava de verdade e o RLS.
- `sql/001_obras.sql`:
  - `obras_perfis` (papel gestor, aprovador, obra; ativo; aprovado_em),
    funcoes `obras_papel()`, `obras_tem_acesso()`, `obras_e_gestor()`,
    `obras_aprova()`; `obras_registrar(nome, papel)` para a tela Criar conta;
    `obras_promover_gestor(email)` para socorro; gatilho que barra
    auto-promocao.
  - `obras_empreendimentos` (nome unico sem diferenca de maiusculas, cidade,
    inicio, previsao de entrega, ativo) e `obras_etapas` (em ordem, com
    situacao a fazer / em andamento / concluida). Gatilho cria as quatro
    etapas padrao em todo empreendimento novo.
  - `obras_atualizacoes` (empreendimento, etapa, titulo, texto, percentual,
    data, situacao aguardando / aprovada / ajuste / recusada, quem enviou,
    quem decidiu e quando, observacao do aprovador, publicado_em). Gatilho:
    nasce aguardando em nome de quem esta logado; so quem aprova muda a
    situacao; quem enviou corrige enquanto aguarda ou esta em ajuste, e ao
    corrigir volta para a fila.
  - `obras_eventos` (a linha do tempo: enviada, reenviada, aprovada, ajuste,
    recusada, nota), preenchida por gatilho a cada mudanca de situacao.
  - `obras_fotos` (caminho no Storage, legenda, ordem) e o bucket `obras`,
    publico para leitura, com upload so de quem tem acesso e sempre na pasta
    do proprio `user_id`.
  - Funcoes `obras_cliente_do_empreendimento(id)` e `obras_ve_atualizacao(id)`
    e as politicas que deixam o cliente da Central ler so o aprovado.

## Conferencia antes de cada commit

- DOM falso (jsdom) com um Supabase de mentira: entrar, senha errada, esqueci
  a senha, cada papel vendo as abas que deve (obra so Enviar; aprovador Enviar
  e Aprovar; gestor tudo), login sem perfil, conta desativada, criar conta (o
  primeiro vira gestor; o segundo aguarda e e liberado; recusa; e-mail
  repetido), empreendimentos (cadastro com as etapas padrao, edicao, exclusao
  so sem atualizacoes, erro legivel de nome repetido), equipe (troca de papel,
  desativar, reativar).
- Navegador (puppeteer) em 1440 e 390 com o Supabase de mentira servido no
  lugar do CDN: telas fotografadas, nada vazando, toque de 44px no celular.

## Decisoes registradas

- **Mesmo Supabase e mesmo login** da Central e do CRM, com prefixo `obras_`.
  Decisao dela em 07/10/2026.
- **Cadastro com liberacao do gestor**, igual ao CRM, em vez de convite por
  e-mail: nao precisa de funcao no servidor nem de chave de servico na Vercel.
- **Lista propria de empreendimentos**, com o nome igual ao da Central, para
  o painel nao depender do CRM estar no ar.
- **Nada entra direto na `main`**: cada etapa em branch propria, preview na
  Vercel, merge com aprovacao.
- **Quem sai fica inativo**, nunca e apagado: o historico das atualizacoes
  precisa continuar apontando para a pessoa.
- **Fim de linha LF** forcado pelo `.gitattributes`.
