# OBS-Pomodoro-Timer
OBS Pomodoro Timer


# 📦 OBS Pomodoro Timer (v5)

Advanced Pomodoro Timer Script for OBS Studio with subject tracking, animations, logging, and automation.

---

## 🚀 Installation

1. Download the `.lua` file from this repository

2. Open OBS Studio

3. Go to:
   Tools → Scripts

4. Click ➕ and select the `.lua` file

---

## ⚙️ Setup

### 1. Add Text Source
- Go to **Sources**
- Add → **Text (GDI+)**
- Name it (e.g. `Timer`)
- Select it inside script settings

---

### 2. Add Alarm Sound
- Add → **Media Source**
- Load your `.mp3` or `.wav`
- Select it as **Alarm Source** in script

---

### 3. Scene Switching (Optional)
Set your scene names in the script:

- Study Scene → your study scene name
- Break Scene → your break scene name

---

### 4. CSV Logging (Optional)
Set file path like: C:\study_log.csv


---

## 🛠️ Configuration

Inside OBS → Scripts panel:

- Study Minutes
- Break Minutes
- Manual Break Minutes
- Total Hours Goal
- Resume Hours / Minutes / Sessions
- Subjects (comma separated)


---

## 🎮 Controls

- Start / Resume → Start timer
- Pause → Pause / unpause
- Skip Phase → Skip study/break
- Stop & Reset → Reset everything

### Manual Break Controls
- Start Break
- +5 Min
- End Break

### Subject Controls
- Next Subject
- Previous Subject

---

## ✨ Features

- Pomodoro study system
- Subject tracking with percentages
- Session + total progress bars
- Auto subject cycling
- Resume support (hours + minutes + sessions)
- Alarm sound integration
- Automatic scene switching
- CSV logging
- Pause screen display
- End-of-session warning
- Smooth fade animation

---

## 📺 Example Output


STUDY
49:32
████████░░░░░░░░
Physics [45%]
SESSION 2 / 10
TOTAL 2h 30m (33%)
████████░░░░░░░░


---

## ⚠️ Notes

- Use **Text (GDI+)**, not regular text source
- Alarm requires a Media Source
- Scene names must match exactly
- CSV logging is optional

---

## 📁 File

- `pomodoro.lua`

---

## 💡 Tips

- Use hotkeys in OBS for faster control
- Keep OBS open to maintain timer state
- Use resume settings if OBS crashes

---

## 🧠 Author

Custom OBS Lua script for advanced study sessions.

## 👨‍💻 Creator

**Pamuda**


