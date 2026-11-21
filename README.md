# MOBA Protótipo (mobile)

Protótipo de MOBA "tipo Dota" para celular, feito em **Godot 4.7** (GDScript, renderer Compatibility).

**Etapa 1.5 (atual): versão 3D** — câmera isométrica, joystick virtual, botão ATACAR, 4 habilidades (NOVA, SALTO, FÚRIA, METEORO no nível 3), heróis e creeps animados (KayKit, CC0), torres e castelos 3D, rio com ponte, luz/sombras.

**Etapa 1 (2D, em `prototipo_2d/`):** 1 lane contra bot — herói controlado por toque/mouse, ataque automático, habilidade ONDA (dano em área), upgrade +FORÇA com ouro, ondas de creeps a cada 30s, 2 torres + base por lado (torres protegidas por camada), herói bot inimigo, níveis/XP, ouro, renascimento, tela de vitória/derrota.

**v0.7.0:** nova heroína Assassina Fantasma (ver seção abaixo).

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

## Névoa de guerra (v0.6.0)
Cada time só vê ao redor das próprias unidades: herói 12 m, creeps 8 m, torres 12 m, base 14 m, Sentinela 14 m e a fonte 16 m.
Fora disso o mapa escurece, inimigos e acampamentos neutros somem (tela e minimapa) e ninguém pode mirar neles, inclusive os bots.
Torres e bases inimigas continuam visíveis. O mato alto continua escondendo heróis. Para testar sem névoa: `--nofog`.

## Torres estilo Dota (v0.6.1)
Torres novas geradas por `tools/build_towers.gd`: Radiant (pedra branca, brilho azul, máscaras douradas e coroa) e Dire (basalto escuro, brilho vermelho, chifres de osso). Para mudar o visual, edite o script e rode `godot --headless -s res://tools/build_towers.gd`.

## Assassina Fantasma (v0.7.0)
Nova heroína corpo a corpo, inspirada na Phantom Assassin (Mortred) do Dota 2: frágil, rápida e letal. Modelo: KayKit Rogue (CC0) com duas adagas e textura recolorida em aço escuro/preto com detalhes azul-petróleo (`assets/chars/Rogue_assassina_texture.png`). No 3v3 padrão ela é o bot do meio do time vermelho (o Orc continua disponível na tela de escolha).

Atributos: 740 de vida, 50 de dano, alcance 1,4, ataque a cada 0,9s, velocidade 6,3.

| # | Habilidade | Recarga | Efeito |
|---|---|---|---|
| 1 | ADAGA | 7s | Arremessa uma adaga num inimigo (até 8m; arraste para mirar, toque mira o mais perto): 60 + 15×nível + 50% do dano de ataque (físico) e lentidão de 2,5s. Pode dar crítico (Misericórdia). |
| 2 | GOLPE FANTASMA | 10s | Teleporta para junto de uma unidade a até 7m. Toque: inimigo. Arrastar: inimigo ou aliado (fuga). Num inimigo: +80% de velocidade de ataque por 3s. |
| 3 | BORRÃO | 18s | Fica invisível para o time inimigo por 6s + 0,25s/nível: some da tela e do minimapa e não pode ser alvo (habilidades em área ainda acertam). É revelada perto de heróis inimigos (6,5m) ou dentro do alcance de torres/base inimigas. **Passiva Imaterial:** 18% + 1%/nível (máx. 30%) de chance de esquivar ataques básicos ("ESQUIVA"). |
| 4 | MISERICÓRDIA (Golpe de Misericórdia) | passiva, Nv 3 | 15% de chance de crítico ×2,5 (+0,1 por nível acima do 3) nos ataques básicos e na parte de ataque da Adaga; número vermelho grande. Não vale contra torres/base. No HUD o 4º botão aparece como "PASSIVA" (sem recarga; tocar mostra a chance e o multiplicador). |

Bots: arremessam a Adaga para cutucar/finalizar e dar o último golpe em creeps, usam o Golpe Fantasma em heróis que conseguem vencer, usam o Borrão para chegar escondidos em heróis fracos ou para fugir (com Adaga no perseguidor e Golpe Fantasma em aliado mais perto da base). Rota de itens: Poção, Botas, Luvas, Espada, Satânico, BKB.

## Assinatura do APK
A partir da v0.7.0 o APK é assinado com a chave de debug em `tools/android/debug.keystore` (alias `androiddebugkey`, senha `android`). Para que as próximas versões instalem por cima, copie esse arquivo para `~/.local/share/godot/keystores/debug.keystore` (ou aponte Editor Settings > Export > Android > Debug Keystore para ele) antes de exportar.
