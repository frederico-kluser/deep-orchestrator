# deep-orchestrator

Orquestrador autônomo multi-agente para Claude Code — planeja, divide em ondas, cria worktrees isoladas, delega, revisa adversarialmente, integra via squash-merge com gate, e commita tudo ao final **sem perguntar nada ao usuário**.

## Como funciona

O deep-orchestrator nunca escreve código. Ele atua como arquiteto-distribuidor: projeta o plano, divide o trabalho em ondas topológicas, cria e batiza worktrees isoladas do Git (uma por sub-agente), dispara os agentes em paralelo, aplica revisão adversarial, integra cada resultado via `git merge --squash` um a um com gate (build + testes + linter) entre merges, remove worktree + branch + commits intermediários ao fim de cada onda, e commita tudo ao final.

```
ANALYZE  →  PLAN  →  EXECUTE-ONDA (repeat)  →  COMMIT-FINAL
```

### Fases

| Fase | Nome | O que faz |
|------|------|-----------|
| 1 | **ANALYZE** | Lê o prompt, mapeia a estrutura do repositório, identifica subsistemas, classifica greenfield/brownfield, localiza golden masters |
| 2 | **PLAN** | Decompõe a tarefa em sub-tarefas atômicas, identifica o grafo de dependências, organiza em ondas topológicas, define o mapa de propriedade de arquivos, batiza cada worktree, escreve os prompts de delegação |
| 3 | **EXECUTE-ONDA** | Para cada onda: commit prep (se necessário) → cria worktrees → dispara agentes em paralelo → barreira → revisão adversarial → squash-merge um a um com gate → limpeza de worktrees/branches → handoff para a próxima onda |
| 4 | **COMMIT-FINAL** | Remove o TASK_PLAN.md, roda o gate completo, commita os arquivos restantes, varredura final de limpeza, produz relatório |

### Regras fundamentais

1. **Nunca escreve código** — delega tudo a sub-agentes
2. **Nunca pergunta ao usuário** — autonomia total, infere com confiança
3. **Trabalho completo, do início ao commit** — nunca entrega trabalho parcial
4. **Worktree é a unidade de isolamento** — cada sub-agente trabalha em sua própria worktree Git com nome descritivo (ex.: `onda1-cache-service`)
5. **Squash-merge um a um, nunca octopus** — integração sequencial com gate entre merges
6. **Worktree nasce nomeada e morre no fim da própria onda** — limpeza imediata após gate verde

## Instalação

```bash
# Clone o repositório
git clone <repo-url> ~/Projects/deep-orchestrator

# Adicione ao seu projeto como skill
mkdir -p .claude/skills/deep-orchestrator
cp SKILL.md .claude/skills/deep-orchestrator/
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

1. Analisar o repositório e identificar os subsistemas afetados
2. Criar um plano com 2 ondas:
   - **Onda 1 (Fundação):** `onda1-cache-service` (CacheService genérico) + `onda1-schema-busca` (mapear schema de busca) — paralelo
   - **Onda 2 (Implementação):** `onda2-endpoint-busca` (endpoint com cache + testes)
3. Executar cada onda com barreira, revisão adversarial, squash-merge com gate, e limpeza
4. Commitar tudo e entregar o relatório

Ao final, o histórico do branch principal terá exatamente 3 commits squash (um por sub-agente), zero worktrees remanescentes e zero branches `wt/*`.

## Estrutura do repositório

```
deep-orchestrator/
├── README.md          # Este arquivo
└── SKILL.md           # Definição do skill (frontmatter YAML + XML do orquestrador)
```

## Requisitos

- Claude Code (CLI)
- Git
- Acesso ao skill `surf-research-skill` para pesquisa web (usado pelos sub-agentes)
- `project-router` skill no repositório-alvo (roteamento de subsistemas)

## Versão

**2.1.0** — baseado no playbook `modernizar-legado-agentes-paralelos`.

## Licença

MIT
