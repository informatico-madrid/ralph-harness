# Terminal-Bench — Benchmark Estándar para Agentes IA

> **Fuente**: https://www.tbench.ai
> **Creadores**: Stanford × Laude
> **Tipo**: Benchmark de evaluación
> **Fecha de captura**: 2026-05-13

---

## Qué es Terminal-Bench

Terminal-Bench es una colección de benchmarks **Harbor-native** para ayudar a agent makers a cuantificar el dominio terminal de sus agentes. Es el estándar de facto para medir rendimiento de agentes de coding.

---

## Versiones Disponibles

| Versión | Estado | Tareas | Enfoque |
|---------|--------|--------|---------|
| Terminal-Bench 1.0 | Activo | 80 | Tareas originales de terminal |
| Terminal-Bench 2.0 | Activo | 89 | Software engineering, ML, security, data science |
| Terminal-Bench 2.1 | Activo | — | Versión mejorada inspirada en Z.ai Verified |
| Terminal-Bench 3.0 | En desarrollo | — | Next frontier benchmark |
| Terminal-Bench Science | En desarrollo | — | Scientific computing en terminal |

---

## Leaderboard (Top 10 — TB 2.0)

| Rank | Agente | Modelo | Score |
|------|--------|--------|-------|
| 1 | Codex CLI | GPT-5.5 | ~80%+ |
| 2 | ForgeCode | GPT-5.4 | — |
| 3 | TongAgents | Gemini 3.1 Pro | — |
| 4 | ForgeCode | Claude Opus 4.6 | — |
| 5 | SageAgent | GPT-5.3-Codex | — |
| 6 | ForgeCode | Gemini 3.1 Pro | — |
| 7 | Droid | GPT-5.3-Codex | — |
| 8 | Capy | Claude Opus 4.6 | — |
| 9 | Simple Codex | GPT-5.3-Codex | — |
| 10 | Terminus-KIRA | Gemini 3.1 Pro | — |

---

## Ejemplos de Tareas

### System Administration
- **build-linux-kernel-qemu** (medium): Build linux kernel from source, add custom printk, run in QEMU
- **configure-git-webserver** (hard): Configure git server + web server con auto-deploy

### Security
- **crack-7z-hash** (medium): Extract secret from encrypted 7z archive
- **openssl-selfsigned-cert** (medium): Create self-signed TLS certificate with specific requirements

### Data Science
- **reshard-c4-data** (medium): Create compress/decompress scripts for dataset resharding
- **train-fasttext** (hard): Train fasttext model on yelp data, <150MB, >0.62 accuracy

---

## Cómo Usarlo para Medir Tu Agente

1. **Instalar Harbor**: https://harborframework.com
2. **Correr el benchmark**: `harbor run terminal-bench-2`
3. **Ver resultados**: Comparar contra leaderboard público
4. **Iterar**: Cambiar harness, re-correr, medir delta

### Comando de inicio:
```bash
# Via Harbor
harbor run terminal-bench-2 --agent your-agent

# Ver leaderboard
open https://www.tbench.ai/leaderboard/terminal-bench/2.0
```

---

## Relevancia para Harness Engineering

Terminal-Bench es el **único benchmark estandarizado** que mide rendimiento de agentes en tareas de terminal reales. Es el benchmark que usó LangChain para demostrar que harness engineering mejora rendimiento sin cambiar el modelo.

**Flujo recomendado**:
1. Correr baseline en Terminal-Bench
2. Cambiar el harness (prompts, middleware, tools)
3. Re-correr y medir delta
4. Iterar hasta converger

---

## Links

| Recurso | URL |
|---------|-----|
| Sitio principal | https://www.tbench.ai |
| Leaderboard TB 2.0 | https://www.tbench.ai/leaderboard/terminal-bench/2.0 |
| Correr TB | https://harborframework.com/docs/running-tbench |
| Contribuir a TB 3.0 | https://www.tbench.ai/news/tb3-contribution-call |
