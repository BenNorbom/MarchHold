# MarchHold — Tech Tree

Normal starts in the Wood age. Grand Army starts with every research project complete. Both modes use the same buildings and recipes.

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
    hut(["Hut<br/>+6 housing"]):::bld
    stock(["Stockpile"]):::bld
    farm(["Farm"]):::bld
    armory1(["Armory · wood"]):::key
    palisade(["Palisade + gate"]):::bld
    post(["Watch post"]):::bld
    w_items["Wooden spear · wooden shield<br/>militia"]:::item
  end

  subgraph STONE["Stone age"]
    quarry(["Quarry"]):::key
    swall(["Stone wall + gate"]):::bld
    tower(["Stone tower<br/>3 sheltered archer posts"]):::bld
    stable(["Stable"]):::bld
    mine(["Mine on a deposit"]):::bld
    bow["Bow"]:::item
    mounted["Mounted archery research<br/>~60 s"]:::item
  end

  subgraph BRONZE["Bronze age"]
    bronze{{"Usable bronze"}}:::res
    armory2(["Bronze armory research"]):::bld
    ram["Battering ram and bronze equipment"]:::item
  end
  irontech(["Iron Mining at a mine<br/>150 stone + 50 bronze · 120 s"]):::key
  iron{{"Usable iron from iron deposits"}}:::res
  armory3(["Iron armory research"]):::bld
  univ(["University"]):::bld
  gun["Gunpowder research"]:::key
  cannon["Cannon"]:::item
  fire --> hut & stock & farm & armory1 & palisade & post
  armory1 --> w_items
  fire --> quarry --> mine --> bronze
  quarry --> swall & stable & tower & bow
  armory1 --> bow
  stable --> mounted
  bronze --> armory2 --> ram
  bronze --> irontech --> iron --> armory3
  armory2 --> armory3
  iron --> univ --> gun --> cannon
  armory3 --> cannon
```

Every mine produces the usable metal in its deposit. Iron Mining unlocks iron for the whole settlement. Armory research expands the recipes at every armory. Bows become available in the Stone age, and archers and cannons can fire throughout a battle without resupply.

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
