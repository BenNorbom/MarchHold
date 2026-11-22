# MarchHold — Tech Tree

Companion to [PLAN.md](PLAN.md) §6–8. Costs and exact timings are not set yet; the times shown are pacing targets.

**Viewing:** VS Code needs the "Markdown Preview Mermaid Support" extension, then Ctrl+Shift+V. GitHub draws these automatically.

**Legend:** rounded = building · square = item / unit · hexagon = resource

## Full tree

```mermaid
flowchart TB
  classDef bld fill:#6b4f2e,stroke:#3d2c18,color:#fff
  classDef item fill:#3e5c76,stroke:#22384a,color:#fff
  classDef res fill:#4f6b3a,stroke:#2e4222,color:#fff
  classDef key fill:#8a2f2f,stroke:#4a1616,color:#fff

  subgraph WOOD["Wood age · start"]
    fire(["Campfire<br/>housing 8"]):::bld
    hut(["Hut<br/>+5 housing"]):::bld
    stock(["Stockpile"]):::bld
    lodge(["Hunter's lodge"]):::bld
    farm(["Farm"]):::bld
    armory1(["Armory · wood"]):::key
    palisade(["Palisade + gate"]):::bld
    post(["Watch post"]):::bld
    w_items["Wooden spear · wooden shield<br/>bow · stone-tipped arrows · militia"]:::item
  end

  subgraph STONE["Stone age · ~3–5 min"]
    quarry(["Quarry"]):::key
    swall(["Stone wall + gate"]):::bld
    tower(["Stone tower"]):::bld
    house(["House<br/>+10 housing"]):::bld
    granary(["Granary"]):::bld
    stable(["Stable"]):::bld
    ladders["Siege ladders"]:::item
  end

  subgraph BRONZE["Bronze age · ~10–13 min"]
    mine(["Mine<br/>on a deposit"]):::bld
    ores{{"Bronze ore · coal · iron ore"}}:::res
    smelter1(["Smelter"]):::key
    armory2(["Armory · bronze"]):::bld
    b_items["Bronze spear · sword · shield · armor<br/>pike · lance · bronze arrows · ram"]:::item
  end

  subgraph IRON["Iron age · ~17–22 min"]
    smelter2(["Smelter · iron furnace"]):::key
    armory3(["Armory · iron"]):::bld
    i_items["Iron spear · sword · shield · armor<br/>pike · lance · iron arrows"]:::item
  end

  subgraph GUN["Gunpowder age · ~25–30 min"]
    univ(["University"]):::key
    research["Gunpowder research<br/>~90 s"]:::item
    cannon["Cannon + shot"]:::item
  end

  fire --> hut & stock & lodge & farm & armory1
  armory1 --> palisade & post & w_items
  armory1 --> quarry
  quarry --> swall & tower & house & granary & stable & ladders
  quarry --> mine --> ores --> smelter1
  smelter1 -->|"bronze"| armory2 --> b_items
  armory1 -.->|upgrade| armory2
  smelter1 -.->|upgrade| smelter2
  smelter2 -->|"iron"| armory3 --> i_items
  armory2 -.->|upgrade| armory3
  armory3 --> univ --> research --> cannon
```

Red buildings are the ones that open the next age. Dotted arrows are upgrades in place.

## Resources

```mermaid
flowchart LR
  classDef res fill:#4f6b3a,stroke:#2e4222,color:#fff
  classDef ref fill:#7a6a2a,stroke:#4a3f16,color:#fff

  wood{{"Wood"}}:::res
  stone{{"Stone"}}:::res
  food{{"Food"}}:::res
  horses{{"Wild horses"}}:::res
  bore{{"Bronze ore"}}:::res --> bronze{{"Bronze"}}:::ref
  coal{{"Coal"}}:::res --> bronze
  coal --> iron{{"Iron"}}:::ref
  ore{{"Iron ore"}}:::res --> iron
```

## Horses

```mermaid
flowchart LR
  classDef bld fill:#6b4f2e,stroke:#3d2c18,color:#fff
  classDef item fill:#3e5c76,stroke:#22384a,color:#fff
  classDef res fill:#4f6b3a,stroke:#2e4222,color:#fff

  wild{{"Wild herds"}}:::res --> drive["Villagers drive them in"]:::item --> stable(["Stable · Stone age"]):::bld
  stable --> breed["Breeding<br/>~60 s gestation · ~90 s to mature"]:::item --> horse{{"Horses"}}:::res
  horse --> scout["Mounted scouts"]:::item
  horse --> cmdr["Commander's horse"]:::item
  horse --> cav["Cavalry<br/>+ lance · Bronze age"]:::item
  horse --> team["Cannon team<br/>Gunpowder age"]:::item
```

## Combat matchups

```mermaid
flowchart LR
  pike["Pikes"] -->|beat| cav["Cavalry"]
  cav -->|beats| arch["Archers"]
  cav -->|"overruns"| can["Cannons"]
  arch -->|beat| inf["Unshielded infantry"]
  shield["Sword + shield"] -->|beats| pike
  shield -.->|blunts| arch
  can -->|"destroys"| walls["Walls + buildings"]
  can -.->|"inaccurate vs"| inf
```
