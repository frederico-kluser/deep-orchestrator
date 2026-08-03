# deep-orchestrator v3.0.0

![Versão](https://img.shields.io/badge/version-3.0.0-00d4ff)

Orquestrador autônomo multi-agente para Claude Code — planeja, divide em ondas **ILIMITADAS** (com recálculo dinâmico), cria worktrees isoladas, delega, revisa adversarialmente, integra via squash-merge com gate, verifica créditos Brave antes de cada onda, e commita tudo ao final **sem perguntar nada ao usuário**.

## Novidades na v3.0.0

- **Ondas ilimitadas** com recálculo dinâmico — após cada onda, um sub-agente REVISOR DE PLANO analisa os handoffs e o TASK_PLAN.md, propõe novas sub-tarefas ou declara CONVERGÊNCIA. O ciclo só termina por convergência declarada, nunca por um número fixo de ondas.
- **Busca interna Brave** (`scripts/brave-search.sh`) — CLI próprio sobre a Brave Search API que substitui o `surf-search-normal`; não depende mais do `surf-research-skill` nem do CLI `surf-ai`.
- **Verificação de créditos** antes de cada onda (`scripts/check-brave-credits.sh`) — sem créditos, o orquestrador para e informa o usuário (única exceção à autonomia total).
- **ECC Prompts integrados** — 7 templates de prompt (`prompts/ecc-prompts.md`) + 7 skills portados do ECC (`prompts/ecc-skills.md`), incluindo Security Review (AgentShield), Planning Prompt (Plan First) e Prompt Defense Baseline.
- **Prompts de busca para dev** (`prompts/search-prompts.md`) — 8 categorias de busca, sistema de evolução de perguntas (question evolution) e prompts por domínio.
- **HTML Explainer** automático ao final de cada execução (`templates/html-explainer.html`) — de-para de todas as mudanças em 6 abas, salvo como `EXPLAINER.html` na raiz do repositório.

## Como funciona

O deep-orchestrator nunca escreve código. Ele atua como arquiteto-distribuidor: projeta o plano, divide o trabalho em ondas topológicas (quantas forem necessárias — o REVISOR DE PLANO recalcula após cada onda), cria e batiza worktrees isoladas do Git (uma por sub-agente), dispara os agentes em paralelo, aplica revisão adversarial, integra cada resultado via `git merge --squash` um a um com gate (build + testes + linter) entre merges, remove worktree + branch + commits intermediários ao fim de cada onda, e commita tudo ao final.

```
ANALYZE  →  PLAN  →  EXECUTE-ONDA (repeat, ILIMITADO)  →  COMMIT-FINAL
```

### Fases

| Fase | Nome | O que faz |
|------|------|-----------|
| 1 | **ANALYZE** | Lê o prompt, mapeia a estrutura do repositório, identifica subsistemas, classifica greenfield/brownfield, localiza golden masters, verifica que `BRAVE_API_KEY` está definida e que há créditos (`scripts/check-brave-credits.sh --fail-fast`) |
| 2 | **PLAN** | Decompõe a tarefa em sub-tarefas atômicas, identifica o grafo de dependências, organiza em ondas topológicas (número NÃO fixo — o plano é um ponto de partida), define o mapa de propriedade de arquivos, batiza cada worktree, escreve os prompts de delegação, publica o TASK_PLAN.md |
| 3 | **EXECUTE-ONDA** | Para cada onda: verificação de créditos → commit prep (se necessário) → cria worktrees → dispara agentes em paralelo → barreira → **recálculo dinâmico (REVISOR DE PLANO)** → revisão adversarial → squash-merge um a um com gate → limpeza de worktrees/branches → handoff para a próxima onda. Repete até o REVISOR DE PLANO declarar CONVERGÊNCIA |
| 4 | **COMMIT-FINAL** | Remove o TASK_PLAN.md, roda o gate completo, commita os arquivos restantes, varredura final de limpeza, **gera o EXPLAINER.html** (a partir do template `templates/html-explainer.html`) e produz o relatório final |

### Regras fundamentais

1. **Nunca escreve código** — delega tudo a sub-agentes
2. **Nunca pergunta ao usuário** — autonomia total, infere com confiança (única exceção: falta de créditos Brave ou `BRAVE_API_KEY` ausente)
3. **Trabalho completo, do início ao commit** — nunca entrega trabalho parcial
4. **Worktree é a unidade de isolamento** — cada sub-agente trabalha em sua própria worktree Git com nome descritivo (ex.: `onda1-cache-service`)
5. **Squash-merge um a um, nunca octopus** — integração sequencial com gate entre merges
6. **Worktree nasce nomeada e morre no fim da própria onda** — limpeza imediata após gate verde
7. **Verificar créditos Brave antes de cada onda** — `scripts/check-brave-credits.sh --fail-fast`; sem créditos, nenhuma worktree é criada e nenhum sub-agente é disparado

## Estrutura do repositório

```
deep-orchestrator/
├── README.md                    # Este arquivo
├── SKILL.md                     # Definição do skill v3.0.0 (frontmatter YAML + XML do orquestrador)
├── scripts/
│   ├── brave-search.sh          # CLI de busca Brave (substitui o surf-search-normal)
│   └── check-brave-credits.sh   # Verificador de créditos da Brave Search API
├── prompts/
│   ├── ecc-prompts.md           # 7 templates de prompt portados do ECC
│   ├── ecc-skills.md            # 7 skills ECC portados
│   └── search-prompts.md        # Prompts de busca otimizados para dev
└── templates/
    └── html-explainer.html      # Template do HTML explainer (6 abas, Bootstrap 5)
```

## Requisitos

- Claude Code (CLI)
- Git
- **Brave Search API key** — `export BRAVE_API_KEY=<chave>` (https://api.search.brave.com/app/keys); o plano gratuito inclui ~$5/mês de créditos
- `curl` e `jq` (usados pelos scripts de busca)
- `project-router` skill no repositório-alvo (roteamento de subsistemas)

## Instalação

```bash
# Clone o repositório
git clone <repo-url> ~/Projects/deep-orchestrator

# Adicione ao seu projeto como skill — copie o diretório INTEIRO,
# pois scripts/, prompts/ e templates/ são referenciados pelo SKILL.md
mkdir -p .claude/skills/deep-orchestrator
cp -r SKILL.md scripts prompts templates .claude/skills/deep-orchestrator/

# Defina a chave da Brave Search API
export BRAVE_API_KEY=<chave>
```

## Uso

```
/deep-orchestrator <descrição da tarefa>
```

### Triggers

O skill é ativado automaticamente com frases como:

- "orquestre isso"
- "divida essa tarefa"
- "coordene múltiplos agentes"
- "resolva do início ao fim"
- "não me pergunte nada"
- "autônomo"
- "toca o barco"

### Quando usar

Tarefas complexas que se beneficiam de decomposição em ondas paralelas — especialmente quando você quer uma solução completa do início ao fim sem interrupções. **Nunca use para tarefas triviais de um passo só.**

### Exemplo

```
/deep-orchestrator Adicionar endpoint de busca com cache a uma API REST
```

O orquestrador vai:

1. Analisar o repositório e identificar os subsistemas afetados (verificando `BRAVE_API_KEY` e créditos antes)
2. Criar um plano inicial com 2 ondas:
   - **Onda 1 (Fundação):** `onda1-cache-service` (CacheService genérico) + `onda1-schema-busca` (mapear schema de busca) — paralelo
   - **Onda 2 (Implementação):** `onda2-endpoint-busca` (endpoint com cache + testes)
3. Executar cada onda com barreira, recálculo dinâmico (REVISOR DE PLANO), revisão adversarial, squash-merge com gate e limpeza — ondas adicionais podem surgir se o revisor detectar novas sub-tarefas
4. Commitar tudo, gerar o `EXPLAINER.html` e entregar o relatório

Ao final, o histórico do branch principal terá exatamente 3 commits squash (um por sub-agente), zero worktrees remanescentes e zero branches `wt/*`.

## Versão

**3.0.0** — Brave Search interno, ondas ilimitadas, ECC prompts, verificação de créditos, HTML explainer.

## Licença

MIT
