# Project Sylvanas - Classic Class OpenSource Plugin System

Welcome to the **Project Sylvanas Classic Era/HardCore Class Plugin System**!  
This project provides a modular plugin architecture for automating WoW Classic gameplay. Each class has its own folder and dedicated plugin.
This project is created to encourage open source class rotations from the community!

---

## 🌟 Supported Classes

- **Shaman** (implemented and actively maintained)
- *Other classes coming soon!*
    - Each class will have its own folder and README.

---

## Repository Structure

```
PS_Classic_Class_Plugin/
│
├── Shaman/
│   ├── main.lua
│   ├── header.lua
│   ├── <anyOtherSupportingCode>
│   └── README.md
├── <OtherClass>/
│   └── README.md
└── README.md (this file)
```
- Each class folder contains its own `main.lua`, `header.lua` and `README.md`.
- This README gives an overview; **see individual class folders for detailed documentation.**
---


## Shaman Plugin Highlights

- Healer Mode: Smart healing for self and party using health prediction.
- DPS Mode: Solo leveling DPS logic prioritizing Flame Shock/Earth Shock.
- Weapon Imbues: Automatic application of Windfury, Rockbiter, etc.
- Interrupts: Auto Earth Shock interrupts on enemy casts.
- Utility: Auto Tremor Totem for fears/sleeps, logging of buffs/spells.
- All features are automatic, with UI toggles for modes and options.

---

## Extending and Contributing

- **To add a new class:**
    1. Create a new folder (e.g., `Priest/`).
    2. Add a `main.lua` and a `README.md` describing your logic/features.
    3. Follow the plugin structure demonstrated in the Shaman plugin.
- **To improve existing plugins:**
    - See individual class README for TODOs and suggestions.
    - Pull requests are welcome!

---

## 💬 Support & Community

Questions or suggestions? Open an issue or join the Project Sylvanas community!
