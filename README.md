# MOBA Protótipo (mobile)

Protótipo de MOBA "tipo Dota" para celular, feito em **Godot 4.7** (GDScript, renderer Compatibility).

**Etapa 1 (atual):** 1 lane contra bot — herói controlado por toque/mouse, ataque automático, habilidade ONDA (dano em área), upgrade +FORÇA com ouro, ondas de creeps a cada 30s, 2 torres + base por lado (torres protegidas por camada), herói bot inimigo, níveis/XP, ouro, renascimento, tela de vitória/derrota.

Próximas etapas: mapa completo (3 lanes + selva), mais heróis/habilidades, depois online.

## Controles
- Toque/arraste (ou clique/arraste) para mover; toque num inimigo para atacar.
- **ONDA** (ou Q/Espaço): dano em área. **+FORÇA** (ou W): compra +dano e +vida.

## Build web
```
godot --headless --export-release "Web" build/web/index.html
```
Export sem threads (roda no GitHub Pages sem cabeçalhos COOP/COEP). A versão jogável fica na branch `gh-pages`.

Todos os direitos reservados.
