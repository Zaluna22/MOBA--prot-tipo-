# MOBA Protótipo (mobile)

Protótipo de MOBA "tipo Dota" para celular, feito em **Godot 4.7** (GDScript, renderer Compatibility).

**Etapa 1.5 (atual): versão 3D** — câmera isométrica, joystick virtual, botão ATACAR, 4 habilidades (NOVA, SALTO, FÚRIA, METEORO no nível 3), heróis e creeps animados (KayKit, CC0), torres e castelos 3D, rio com ponte, luz/sombras.

**Etapa 1 (2D, em `prototipo_2d/`):** 1 lane contra bot — herói controlado por toque/mouse, ataque automático, habilidade ONDA (dano em área), upgrade +FORÇA com ouro, ondas de creeps a cada 30s, 2 torres + base por lado (torres protegidas por camada), herói bot inimigo, níveis/XP, ouro, renascimento, tela de vitória/derrota.

Próximas etapas: mapa completo (3 lanes + selva), mais heróis/habilidades, depois online.

## Controles
- Joystick (metade esquerda da tela) ou WASD/setas para mover.
- ATACAR (ou Espaço); habilidades 1-4; LOJA (ou B) abre a loja; itens ativos tocando no slot (ou 5-0).

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


## Loja (v0.5.0)
Botão LOJA no canto superior direito (substitui o +FORÇA). Só compra/vende perto da sua fonte. 6 slots; vender devolve 50%.

| Item | Preço | Efeito |
|---|---|---|
| Botas | 300 | +25% velocidade de movimento |
| Poção (consumível, até 5) | 60 | Cura 300 em 8s; corta se levar dano de herói |
| TP (consumível, até 3) | 100 | 3s canalizando e volta à base; mover/atordoar/dano de herói cancela |
| Sentinela (consumível, até 3) | 75 | Planta visão por 90s: revela o mato alto num raio de 8m (máx. 4 por time) |
| Espada Longa | 450 | +15 de dano |
| Coração Troll | 500 | +250 vida, +4 regeneração |
| Luvas Pressa | 450 | +20% velocidade de ataque |
| Adaga Blink | 1400 | Ativo: teleporte de 8m (recarga 14s; trava 3s após dano de herói) |
| Cetro Arcano | 1600 | -25% recarga das habilidades, +150 vida |
| Machado Negro (BKB) | 1800 | Ativo: 5s imune a atordoar/lentidão e -40% de dano (recarga 40s) |
| Satânico | 1700 | +20 dano, 20% roubo de vida |

Bots compram seguindo uma rota (à distância / corpo a corpo) e usam Poção e BKB.
