# MOBA Protótipo (mobile)

Protótipo de MOBA "tipo Dota" para celular, feito em **Godot 4.7** (GDScript, renderer Compatibility).

**Etapa 1.5 (atual): versão 3D** — câmera isométrica, joystick virtual, botão ATACAR, 4 habilidades (NOVA, SALTO, FÚRIA, METEORO no nível 3), heróis e creeps animados (KayKit, CC0), torres e castelos 3D, rio com ponte, luz/sombras.

**Etapa 1 (2D, em `prototipo_2d/`):** 1 lane contra bot — herói controlado por toque/mouse, ataque automático, habilidade ONDA (dano em área), upgrade +FORÇA com ouro, ondas de creeps a cada 30s, 2 torres + base por lado (torres protegidas por camada), herói bot inimigo, níveis/XP, ouro, renascimento, tela de vitória/derrota.

Próximas etapas: mapa completo (3 lanes + selva), mais heróis/habilidades, depois online.

## Controles
- Joystick (metade esquerda da tela) ou WASD/setas para mover.
- ATACAR (ou Espaço); habilidades 1-4; +FORÇA (ou B) compra +dano e +vida.

Arte 3D: KayKit por Kay Lousberg (CC0), ver `assets/LICENSE-KayKit.txt`.

## Build web
```
godot --headless --export-release "Web" build/web/index.html
```
Export sem threads (roda no GitHub Pages sem cabeçalhos COOP/COEP). A versão jogável fica na branch `gh-pages`.

Todos os direitos reservados.


## Etapa 1.6
- Performance no celular: renderer Compatibility, resolução 3D 65% e DPR máx 2 no mobile, sem sombras/glow/luzes pontuais no celular, malhas dos personagens mescladas, pools de creeps e efeitos, física a 30 Hz, HUD em lote.
- Heróis: Elfo e Orc do pack "Characters - Fantasy Races" da Quaternius (licença QAL: uso em jogos ok, sem redistribuir os arquivos; por isso ficam fora do repositório, em assets/quaternius/, gerados por tools/slim_glb.py). Animações: Universal Animation Library (CC0).
