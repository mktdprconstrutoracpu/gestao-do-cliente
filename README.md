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
| **Gestao de obras** (rota `#enviar`) | papel `obra` (e tambem aprovador e gestor) | Entra com o proprio login e envia as fotos e o andamento da obra, mes a mes. Ve so o que ela mesma enviou e a situacao de cada envio |
| **Aprovacao** (rota `#aprovar`) | papel `aprovador` (Luana, Rodrigo) e `gestor` | A fila do que a obra enviou. Aprova, pede ajuste ou recusa. Nada chega ao cliente sem passar por aqui |

Os nomes das abas sao os dela (09/10/2026): "Gestao de obras" e "Aprovacao".
E as duas opcoes aparecem **antes do login**, na tela inicial (pedido dela no
mesmo dia): quem chega sem sessao escolhe o painel, entra, e cai na aba
escolhida (quem nao pode aprovar cai na Gestao de obras). Sair volta para a
tela inicial; "Trocar de painel" na tela de entrar tambem.

Mais duas abas, so do gestor: **Empreendimentos** (as obras acompanhadas, com
o mesmo nome que a Central usa) e **Equipe** (quem entra e com que papel).

## Etapas

1. **Base**: banco, login, cadastro com aprovacao, as duas abas com a
   estrutura e o historico, Empreendimentos e Equipe.
2. **Enviar**: a ficha completa (empreendimento, etapa, percentual, texto,
   data, fotos no Storage), edicao enquanto aguarda ou esta em ajuste, linha
   do tempo, filtro da fila por situacao.
3. **Aprovar**: aprovar, pedir ajuste ou recusar com observacao,
   marcar a situacao da etapa ao aprovar, voltar para a fila, anotacoes.
   - **Por mes** (esta, 09/10/2026, pedido dela: "a pessoa coloca fotos por
     mes"): a ficha pede o **mes** em vez da data, o titulo ja vem com o
     nome do mes, e as listas de quem envia e a fila de aprovacao ficam
     agrupadas por mes, do mais recente para o mais antigo.
4. **Central lendo as aprovadas**: a pagina "Evolucao da obra" deixa de ser
   demonstracao e passa a mostrar as atualizacoes aprovadas do empreendimento
   da casa do cliente (as travas para isso ja estao no `sql/001_obras.sql`).
5. Aviso ao cliente quando sai atualizacao nova; aviso ao aprovador quando a
   obra envia.

## O que ja tem (etapas 1 a 3)

| Tela | O que faz |
|---|---|
| Tela inicial | Sem sessao, as duas opcoes: **Gestao de obras** e **Aprovacao**. A escolha vira a aba aberta depois do login |
| Entrar | E-mail e senha do Supabase, com o titulo do painel escolhido; "Esqueci a senha" manda o link de recuperacao; "Trocar de painel" volta para a tela inicial |
| Criar conta | Nome, e-mail, senha e papel (obra, aprovador, gestor). O **primeiro** cadastro vira gestor na hora; os seguintes ficam **aguardando liberacao** de um gestor |
| Sem acesso | Login que existe mas nao esta na equipe do painel. Como o login e o mesmo da Central e do CRM, quem ja tem conta cai aqui sem passar por "Criar conta": a tela pede o **nome e o papel** e a pessoa **entra na equipe** na hora (o primeiro vira gestor; os seguintes aguardam um gestor liberar). Quem esta aguardando liberacao, ou foi desativado, ve so o aviso e o botao Sair |
| Enviar atualizacao | Resumo (obras em acompanhamento, enviadas por voce, aguardando, aprovadas) e a tabela do que voce enviou, **agrupada por mes** (o mais recente primeiro), com o mes e a contagem de fotos. "Nova atualizacao" abre a **ficha**: empreendimento (so os em acompanhamento), etapa da obra (a "em andamento" ja vem escolhida), titulo (ja vem com o nome do mes, ex. "Outubro de 2026", e pode ser trocado), texto, andamento geral em %, **mes** (o atual, ou outro ate dois anos atras) e ate 10 fotos, da galeria ou da camera. Tocar numa linha abre a ficha: **editavel** enquanto aguarda ou esta em ajuste (texto e fotos; ao reenviar volta para a fila), **so leitura** depois de aprovada ou recusada. Em ajuste, a observacao do aprovador aparece no alto. Excluir enquanto aguarda. Linha do tempo ao lado |
| Aprovar | Resumo (aguardando, aprovadas, com ajuste, recusadas, obras) e a fila, agrupada por mes, com filtro por situacao (aguardando por padrao, ajuste, aprovadas, recusadas, todas), o mes, quem enviou, quando e o botao Decidir (ou Abrir). A ficha abre com as fotos, a linha do tempo e o bloco **Decisao**: observacao para a obra, **Aprovar** (com a situacao da etapa: a fazer, em andamento, concluida), **Pedir ajuste** e **Recusar** (os dois exigem a observacao, que a obra ve na ficha dela). Em atualizacao ja decidida, **Voltar para a fila** desfaz. Quem ve a ficha pode **anotar** na linha do tempo. O banco carimba quem decidiu e quando. Aviso de cadastros aguardando liberacao (gestor) |
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
- **As fotos**: cada uma e reduzida no navegador (lado maior em 1600px,
  JPEG) antes de subir, para nao pesar no 4G da obra; se o navegador nao
  conseguir ler a imagem (um HEIC, por exemplo), sobe como veio. Sobem uma a
  uma, com o progresso na tela, para o bucket `obras` do Storage, no caminho
  `<user_id>/<atualizacao_id>/<ordem>-<momento>.jpg`: a primeira pasta e o
  proprio `user_id`, e e isso que a politica do Storage exige. Cada arquivo
  vira uma linha em `obras_fotos`. Se uma foto falhar, a atualizacao fica
  gravada e o aviso diz qual nao subiu, para abrir e tentar de novo. Tirar
  uma foto existente apaga o arquivo do Storage e a linha. O bucket e
  publico para leitura: a foto aprovada aparece na Central pelo endereco
  direto.
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
- A ficha no DOM falso, com um Storage de mentira que imita as politicas do
  bucket: obra envia com fotos (validacoes, arquivo que nao e foto recusado,
  caminho na pasta do proprio user_id, linha em `obras_fotos`), ve a aprovada
  so para ler (fotos pelo endereco publico, linha do tempo), exclui a que
  aguarda; ajuste pedido (observacao na tela, tira a foto antiga, poe novas,
  reenvia e volta para aguardando pelo gatilho imitado); aprovador (filtro
  da fila, ficha de outra pessoa so para ver, foto que nao sobe avisando sem
  perder a atualizacao); sem obra em acompanhamento o botao fica desligado.
- Navegador (puppeteer) em 1440 e 390 com o Supabase de mentira servido no
  lugar do CDN e as fotos servidas no lugar do Storage: telas fotografadas
  (inclusive a ficha nova com fotos escolhidas, a ficha so para ver e a
  ficha em ajuste), nada vazando, toque de 44px no celular.

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
- **Atualizacoes por mes** (09/10/2026, pedido dela: "a pessoa coloca fotos
  por mes"): a ficha pede o mes, nao a data. O banco guarda o dia 1 do mes em
  `data_referencia`, sem coluna nova, entao o que ja foi enviado continua
  valendo. Pode haver mais de um envio no mesmo mes (etapas diferentes). As
  listas vem agrupadas por mes, e a Central vai mostrar a obra mes a mes. O
  campo e um select (nao `input type=month`, que o Firefox e o Safari do
  computador nao tem): do mes que vem ate dois anos atras.
