---
epic: ralphharness-rename
title: "RalphHarness Rename"
created: 2026-05-02
owner: informatico-madrid
status: pending
---

# Epic: RalphHarness Rename

**Description:** Rename proyecto de Smart Ralph a RalphHarness. El proyecto dejó de ser fork de tzachbon/smart-ralph y necesita establecerse como proyecto independiente manteniendo "Ralph" (patrón fundamental) y añadiendo "Harness" (arneses de seguridad).

**Goals:**
1. Eliminar todas las referencias a tzachbon/smart-ralph
2. Establecer nuevo brand: RalphHarness
3. Plugin funcional con nuevo nombre y comandos

**Scope:**
- In: Rename directorios plugins, update manifests, grep-sed references, rewrite docs
- Out: Codex skills (pueden quedarse con nombre actual), specs de usuario

## [RH-001] Rename Smart Ralph to RalphHarness | Must Have | XL

**Description:**
Renombrar el proyecto completo de Smart Ralph (ralph-specum) a RalphHarness:

1. Renombrar directorios de plugins:
   - `plugins/ralph-specum/` → `plugins/ralphharness/`
   - `plugins/ralph-speckit/` → `plugins/ralphharness-speckit/`
   - `plugins/ralph-bmad-bridge/` → `plugins/ralphharness-bmad-bridge/`

2. Actualizar plugin manifests (name, version→5.0.0, author→informatico-madrid)

3. Actualizar marketplace.json (owner, source paths)

4. grep-sed masivo: "ralph-specum" → "ralphharness" en:
   - plugins/ralphharness/commands/*.md (13 files)
   - plugins/ralphharness/hooks/scripts/*.sh (8 files)
   - plugins/ralphharness/skills/**/* (skills content)
   - Commands prefix: /ralph-specum: → /ralph-harness:

5. Reescribir docs:
   - README.md (nuevo brand RalphHarness)
   - CLAUDE.md (actualizar Overview y Plugin Structure)
   - LICENSE (copyright → "RalphHarness Project Authors")
   - Eliminar README.fork.md

**Acceptance Criteria:**
```
GIVEN el repositorio actual
WHEN se completa el rename
THEN grep -r "ralph-specum" plugins/ .claude-plugin/ = 0 resultados
AND grep -r "tzachbon" .claude-plugin/ plugins/ = 0 resultados
AND jq -r '.name' plugins/ralphharness/.claude-plugin/plugin.json = "ralphharness"
AND jq -r '.version' = "5.0.0"
AND jq -r '.owner.name' .claude-plugin/marketplace.json = "informatico-madrid"
AND grep "/ralph-harness:" plugins/ralphharness/commands/*.md > 0
AND test -f README.md && grep "RalphHarness" README.md
AND test ! -f README.fork.md
```

**Technical Notes:**
- Usar `git mv` para mantener historial de git
- El comando para grep-sed masivo:
  ```bash
  find plugins/ralphharness -type f \( -name "*.md" -o -name "*.sh" \) \
    -exec sed -i 's/ralph-specum/ralphharness/g; s/; s/ralph-specum:/ralph-harness:/g' {} \;
  ```
- Verificar que state files usan nuevo prefijo `.ralphharness-*`

**Success Metrics:**
- Plugin carga en Claude Code
- `/ralph-harness:help` funciona
- Spec de prueba crea `.ralphharness-state.json`
